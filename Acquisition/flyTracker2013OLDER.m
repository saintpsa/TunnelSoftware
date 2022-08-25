function flyTracks = flyTracker2013
% flyTracks = flyTracker2013
% Real-time fly tracking and stimulus control for testing odor preference
%
% To do:
% 1. Get rid of px idx matching b/w bg detector and main function
% 2. Change RT fly matching to centroid distance < ~15px
% 3. In plot helper function replace 'end' with 'ct'
% 4. Change how the data points are stored:
%   4.1 Create a runningTracks matrix containing toPlot buffer
%   4.2 For each metric, append a new line to an ASCII tmp file each loop
%   4.3 On exit, load the tmp ASCII files into main structure, delete files
% 5. Setup camera ROI selection (adjust background image, glob coord, etc.)
% 6. Add onCleanup callback to salvage data from hard crashes
% 7. Drop duplicate frames occurring at rates > 50fps


clf                             % open clean figure window

global NI AC vid                % pull in nidaq, alicat, and camera objects
                                % defined by initializeTunnels.m





% User-specified parameters
runningLength = 200;            % grabbed frames for tails

dispRate = 50;                  % rate (in frames) at which to update 
                                % tracking display - tradeoff with max
                                % attainable frame rate

chargeTime = 5;                                 % Amount of time (sec)
                                                % given for odor to charge
                                                % before flipping final
                                                % valve

propFields = {'Centroid' 'Orientation' ...     % Get items from regionprops
    'MajorAxisLength' 'PixelIdxList'};





% Begin main script
[stimTimes stim duration] = constructStimulus;  % Setup stimlus timecourse
                                                % for experiment

odorPeriod = presentAir([0.2 0.2]);   % Start flushing tunnels with
                                              % air
                                              
arenaData = detectBackground;             % run bg detection script


nFlies = sum(arenaData.tunnelActive);         % get total number of flies

currentFrame = peekdata(vid,1);               % grab first display frame

h = image(currentFrame); colormap(gray)       % set initial display

colors = hsv(nFlies + 1);   % set colormap for flies
tailCount = 0;              % initialize tail counter (for display)

ct = 0;     % Initialize counter
tic         % Start timer





% This frame-by-frame loop runs continuously for total experiment duration
while toc < duration
    
    ct = ct + 1;  % Update counter

    % 1. On each pass, set stimuli
    if stimTimes(ceil(toc))                  % If this is an odor period...
        
        block = stimTimes(ceil(toc));
        
        epoch = ['Stim ' sprintf('%d', ...   % Used below to label display
            stimTimes(ceil(toc)))];
        
        if ~odorPeriod
            odorTime = clock;   % Each time odor period starts, make
                                % timestamp, wait for chargeTime, then
                                % flip final valve
            
            valves = stim(block).odor(2,:);
            conc = stim(block).odor(1,:);
            odorPeriod = presentOdor(valves, conc);
        end
        
        if etime(clock, odorTime) >= chargeTime
            flipFinalValve        % would be more economical to make this
                                  % conditional: iff state is CLOSED
        end
        
    else                                            % otherwise present air
        epoch = 'Air';  % Used below to label display
        
        if odorPeriod
            conc = [0.2 0.2];
            odorPeriod = presentAir(conc); % Closes FinalValves too
        end
        
    end
    
    
    % 2. Detect flies, extract kinematic data
    currentFrame = peekdata(vid,1);                 % Grab new frame
    flyTracks.times(ct) = now;                      % Timestamp the frame
    delta = arenaData.bg - currentFrame;            % Make difference image
    props = regionprops((delta >= 50), propFields); % Get fly properties
    
    % Mach each props element to preceeding fly idxs - discard non-matches
    % If any overlap exists, call it a match
    
    if ct == 1           % on first pass, load previous idxs from arenaData
        
        %flyTracks.lastPx = arenaData.lastPxIdx; % cell array of previous fly idxs
        
        for z = 1:length(arenaData.lastPxIdx)
            flyTracks.lastPx{z} = [arenaData.lastPxIdx{z}-5; ...
                                   arenaData.lastPxIdx{z}; ... % give some wiggle room
                                   arenaData.lastPxIdx{z}-5];
        end
        
        c = [];
        ori = [];
    end
    
    % Find the props elements corresponding to previous flies
    for i = 1:size(props,1)
        
        matches = cellfun(@(x) intersect(props(i).PixelIdxList, x), ...
            flyTracks.lastPx, 'UniformOutput', 0);
        
        flyIdx = find(~cellfun('isempty',matches)); % find when prop elements
                                                    % match previous fly idxs

        if flyIdx                                                          % FIX so that if a fly goes missing, [] fills the gap
            flyTracks.centroid(ct,:,flyIdx) = single(props(i).Centroid);
            flyTracks.orientation(ct,flyIdx) = single(props(i).Orientation);
            flyTracks.majorAxisLength(ct,flyIdx) = single(props(i).MajorAxisLength);
            flyTracks.lastPx{flyIdx} = props(i).PixelIdxList;              % Does this WORK right?
        end
        
    end
    
    
    % update the display with centroid, major axis, and running tail
    if mod(ct,dispRate) == 0
        [tailCount c ori] = updatePlot(ct, h, currentFrame, duration, epoch, tailCount, flyTracks, runningLength, colors, c, ori);
    end
   
end





% On finish
flyTracks.duration = toc;
flyTracks.bg = arenaData.bg;
flyTracks.tunnels = arenaData.tunnels;
flyTracks.pxRes = arenaData.pxRes;
flyTracks.tunnelActive = arenaData.tunnelActive;
flyTracks = rmfield(flyTracks, 'lastPx');

% Format stimulus info
for s = 1:length(stim)                                                     
    flyTracks.stim{1,s} = ['Stim ' sprintf('%d',s)];
    flyTracks.stim{2,s} = stim(s).times;
    flyTracks.stim{3,s} = stim(s).odor;
end

stop(vid)





    function [tailCount c ori] = updatePlot(ct , h, currentFrame, duration, epoch, tailCount, flyTracks, runningLength, colors, c, ori)

        set(h,'CData',currentFrame)             % update display with current frame
        
        
        timeLeft = round(duration - toc);
        title(['Tracking Flies - ' epoch ' (' sprintf('%d',timeLeft) 's remaining)'])
        tailCount = tailCount + 1;
        
        
        if ct <= runningLength
            tailStartIdx = 1;
        else
            tailStartIdx = size(flyTracks.centroid, 1) - runningLength + 1; % grab the last runningLength positions
        end
        
        
        % calculate major axis limits
        for i = 1:size(flyTracks.majorAxisLength, 2)
            
            r = flyTracks.majorAxisLength(ct,i)/2;
            x = r * cos(flyTracks.orientation(ct,i) * (pi/180));
            y = r * sin(flyTracks.orientation(ct,i) * (pi/180));
            
            lx = [flyTracks.centroid(ct,1,i) + x, ...
                flyTracks.centroid(ct,1,i) - x];
            ly = [flyTracks.centroid(ct,2,i) - y, ...
                flyTracks.centroid(ct,2,i) + y];
            
            majAx{i} = [lx; ly];
        end
        
        
        % update the display with new centroids, major axis, and running tails
        for k = 1:size(flyTracks.centroid, 3)
            
            hold all
            
            if tailCount > 1
                set(c(k), 'XData', flyTracks.centroid(tailStartIdx:end,1,k), ...
                    'YData', flyTracks.centroid(tailStartIdx:end,2,k),...
                    'LineWidth', 2, 'Color', colors(k,:));
                
                set(ori(k), 'XData', majAx{k}(1,:), ...
                    'YData', majAx{k}(2,:),...
                    'LineWidth', 2, 'Color', 'g');
                
            else
                c(k) = plot(flyTracks.centroid(tailStartIdx:end,1,k),...
                    flyTracks.centroid(tailStartIdx:end,2,k),...
                    'LineWidth', 2, 'color', colors(k,:));
                
                ori(k) = plot(majAx{k}(1,:), majAx{k}(2,:), ...
                    'LineWidth',2,'color','g');
                
            end
            
        end
        
        drawnow
        
    end

end

