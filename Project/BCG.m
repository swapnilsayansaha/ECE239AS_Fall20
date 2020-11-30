function [BCG, PR] = BCG(VideoFile, FS, StartTime, Duration)
% BCG: The Ballistocardiographic (BCG) Motion Method from: Balakrishnan, G., Durand, F., & Guttag, J. (2013). Detecting pulse from head motions in video. In Computer Vision and Pattern Recognition (CVPR), 2013 IEEE Conference on (pp. 3430-3437). IEEE. DOI: 10.1109/CVPR.2013.440
%
%   Inputs:
%       VideoFile               = Video file path.
%       FS                      = Video framerate (fps).
%       StartTime               = Timepoint at which to start process (default = 0 seconds).
%       Duration                = Duration of the time window to process (default = 60 seconds).

%   Outputs:
%       BVP                     = Processed Blood Volume Pulse (BVP).
%       PR                      = Estimated Pulse Rate (PR) from processed BVP timeseries using peak in periodogram.

% Daniel McDuff, Ethan Blackford, January 2019
% Copyright (c)
% Licensed under the MIT License and the RAIL AI License.
% Edited by Paawan Garg, UCLA

f = waitbar(0,'Frames processed','Name','Running BCG...');
%% Parameters
LPF = 0.7; %low cutoff frequency (Hz) - specified as 0.75 Hz in reference
HPF = 5.0; %high cutoff frequency (Hz) - specified as 5.0 Hz in reference

%% Add Backup Functions
if(~license('test', 'Statistics_Toolbox'))
    addpath([cd '\optional\']);%GNU GPL quantile.m function
end

%% Load Video:
VidObj = VideoReader(VideoFile);
VidObj.CurrentTime = StartTime;
TotalFrames = ceil(VidObj.duration)*FS;
FramesToRead=ceil(Duration*VidObj.FrameRate); %video may be encoded at slightly different frame rate

%% Initialize Face Tracking
BBox = [1,1,VidObj.width,VidObj.height];

MinQ = 0.01;
VidFrame = readFrame(VidObj);

try%allow to run example video file without Computer Vision Toolbox by loading tracking results in catch
    Points0 = detectMinEigenFeatures(rgb2gray(VidFrame),'ROI',BBox,'MinQuality',MinQ);
    
    
    if length(Points0) < 5
        BCG=NaN; PR=NaN;
        return
    end
    
    tracker = vision.PointTracker;
    initialize(tracker,Points0.Location,VidFrame);
    
    %% Read Video and Spatially Average:
    T = zeros(FramesToRead-1,1);%Initialize time vector
    Y = zeros(FramesToRead-1,size(Points0.Location,1));%initialize Y
    FN = 0;
    while hasFrame(VidObj) && (VidObj.CurrentTime <= StartTime+Duration)
        FN = FN+1;
        T(FN) = VidObj.CurrentTime;
        VidFrame = readFrame(VidObj);
        

        %position for optional face detection/tracking - originally specified in reference as using Viola Jones, 2004 to isolate face rectangle and exclude region including the eyes
        [Points, ~] = step(tracker,VidFrame);
        Y(FN,:) = Points(:,2);%y, vertical component
    waitbar((FN+(StartTime*FS))/TotalFrames,f,sprintf('Frames Processed: %d out of %d',FN+(StartTime*FS),TotalFrames));
    end
    
catch TrackError%optional catch to run example without Computer Vision Toolbox by loading tracking results in catch
    if(strcmp(TrackError.message,'Undefined function ''detectMinEigenFeatures'' for input arguments of type ''uint8''.'))
        [VideoFilePath,VideoFileName,VideoFileExt] = fileparts(VideoFile);
        if(strcmp([VideoFileName VideoFileExt],'video_example.mp4'))%only run for example video
            if(exist(VideoFile,'file'))%only allow to proceed for the example video where we have the results of the point tracking
                fprintf('Tracking could not be completed without the Computer Vision Toolbox.\nLoading previously run tracking results for ''video_example.mp4''.\n')
                load([VideoFilePath '\BCGTracking.mat']);%contains Y and T results for video_example.mp4 run with defaults FS=30, StartTime=0, and Duration=60
            end
        else%show error - can only avoid tool box requirement to run video_example with loaded tracking results
            TrackError;
        end
    else%some other error
        TrackError;
    end
end% end try-catch

%originally specified in reference with cubic-spine interpolation to 250Hz (from 30 Hz) to match sampling rate of ECG device.

%% Signal Processing:
%Remove erratic feature points - points whose max movement between consecutive frames exceeds the mode of the distribution of max motions
MaxYMotions=max(floor(diff(Y,1,2)));
UnstableMask=MaxYMotions>mode(MaxYMotions);
YS=Y(:,~UnstableMask);

NyquistF = 1/2*FS;
[B,A] = butter(3,[LPF/NyquistF HPF/NyquistF]);%5th order butterworth filter in reference
Y_Filt = filtfilt(B,A,double(YS));

Y_Filt2 = bsxfun(@minus, Y_Filt, Y_Filt(1,:));
YL2 = sqrt(sum(Y_Filt2.^2,2));
YMask = YL2<=quantile(YL2,.75);

Y_Filt3=Y_Filt2(YMask,:);
[Coeff, ~, ~] = pca(Y_Filt3);

Score = bsxfun(@minus, Y_Filt, mean(Y_Filt))/Coeff';

%% Component Selection
F=find(T>0);
[Pxx,F2] = plomb(Score(F,1:5),T(F));%only evaluate first 5 components

FMask = (F2 >= LPF)&(F2 <= HPF);
FRange = F2(FMask);
R = zeros(1,5);
for i = 1:5
    [MaxP,IDXP] = max(Pxx(:,i));
    R(i) = (MaxP+Pxx(IDXP*2,i))/sum(Pxx(:,i));
end
[~,NumPC] = max(R);

%% PR
PR = FRange(argmax(Pxx(FMask,NumPC),1))*60;

BCG_F = Score(:,NumPC);

BCG_N = BCG_F-mean(BCG_F);
BCG = BCG_N;

%% Remove Backup Functions
if(~license('test', 'Statistics_Toolbox'))
    rmpath([cd '\optional\']);%GNU GPL quantile.m function
end

end%end function
