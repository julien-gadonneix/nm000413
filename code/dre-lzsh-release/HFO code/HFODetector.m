function [RippleRate,FastRippleRate,Ripples,FastRipples] = HFODetector(Data,SamplingRate)

% [RippleRate,FastRippleRate,Ripples,FastRipples] = HFODetector(Data, SamplingRate)
% 
% Automatic ripple and fast ripple detector. The input signals are given in
% the matrix Data, with each column corresponding to a different channel
% and each row corresponding to a different time sample. The sampling rate
% is given by SamplingRate. 
% Ripples are detected in the 80-250 Hz frequency band, and fast ripples 
% in the 250-500 Hz. If the sampling rate is not high enough only the 
% frequencies below sampling rate x0.45 are analyzed.
% RippleRate and FastRippleRate are vectors with one element per channel,
% and give the rates of detected events per minute.
% Ripples and FastRipples are lists of detected events. They have one row
% per event and five columns. Column 1 indicates the channel in which the
% event was detected, column 2 the frequency, column 3 the start sample,
% column 4 the duration (in samples), column 5 the strenght (against which
% the threshold is compared).


% Algorithm parameters
WindowLength=5;     % Background moving window length [seconds]
Threshold=3;    % Thresholdeshold (RMS of background times this value)
% Initializations
Duration=size(Data,1)/SamplingRate/60;
NumberOfSamples=size(Data,1);
WindowLength=round(WindowLength*SamplingRate);
if NumberOfSamples<WindowLength+1, WindowLength=NumberOfSamples-3; end
MinimumSeparation=0.008; % Minimum separation between events [seconds]
MinimumSeparation=round(MinimumSeparation*SamplingRate);
MinimumSeparationRipple=0.02; % Minimum separation between events [seconds]
MinimumSeparationRipple=round(MinimumSeparationRipple*SamplingRate);
BandpassFilterOrder=200; 
NarrowbandFilterOrder=508;
NumberOfChannels=size(Data,2);
% Filters (one general bandpass filter and many narrowband filters)
BandpassFilter=firpm(BandpassFilterOrder,[0 65 80 min(0.45*SamplingRate,...
    500) min(0.45*SamplingRate+15,515) 0.5*SamplingRate]*2/SamplingRate,...
    [0 0 1 1 0 0],[10 1 1]);
FrequencyBands=[80 90 105 120 140 160 185 215 250 285 330 380 435 500]...
    /SamplingRate;
FrequencyBands(FrequencyBands>.45)=[];
NumberOfBands=length(FrequencyBands)-1;
NarrowBandFilters=zeros(NumberOfBands,NarrowbandFilterOrder+1);
for ii=1:NumberOfBands
    NarrowBandFilters(ii,:)=firpm(NarrowbandFilterOrder,[0,...
        FrequencyBands(ii)-7/SamplingRate FrequencyBands(ii)+3/...
        SamplingRate FrequencyBands(ii+1)-3/SamplingRate,...
        FrequencyBands(ii+1)+7/SamplingRate .5]*2,[0 0 1 1 0 0],[10 1 1]);
end
FrequencyBands=(FrequencyBands(1:end-1)+FrequencyBands(2:end))/2;
% Minimum length of the Events (narrowband filter effective duration plus
% four cycles of the band central frequency.
MinimumLength=round(sqrt(sum(repmat((-NarrowbandFilterOrder/2:...
    NarrowbandFilterOrder/2).^2,NumberOfBands,1).*NarrowBandFilters.^2,...
    2)./sum(NarrowBandFilters.^2,2))+4./FrequencyBands');
% Initializations
Event=zeros(round(NumberOfChannels*20*Duration),11);
Offset=(NarrowbandFilterOrder+BandpassFilterOrder)/2;
EventCounter=0;
% Bandpass filtering
BanspassSignal=filter(BandpassFilter,1,[Data; zeros(BandpassFilterOrder...
    /2,NumberOfChannels)]); 
BanspassSignal(1:BandpassFilterOrder/2,:)=[];
% For each frequency band
for ii=1:NumberOfBands
    % Narrow band signal
    NarrowbandSignal=filter(NarrowBandFilters(ii,:),1,[BanspassSignal;...
        zeros(NarrowbandFilterOrder/2,NumberOfChannels)]); 
    NarrowbandSignal(1:NarrowbandFilterOrder/2,:)=[];
    % Compute RMS (squared) value in 4 cycles window
    FourCyclesHalfDuration=floor(2/FrequencyBands(ii));
    FourCyclesDuration=ones(1,2*FourCyclesHalfDuration+1)/...
        (2*FourCyclesHalfDuration+1);
    RMSSignal=sqrt([filter(FourCyclesDuration,1,NarrowbandSignal.^2);...
        zeros(FourCyclesHalfDuration,NumberOfChannels)]); 
    RMSSignal(1:FourCyclesHalfDuration,:)=[];
    % Compute RMS of background (moving window)
    MovingBackground=RMSSignal; 
    MovingBackground(1:WindowLength,:)=repmat(mean(RMSSignal(1:...
        WindowLength,:)),WindowLength,1); 
    IterativeBackgroundEstimator=RMSSignal;
    for jj=WindowLength+1:NumberOfSamples
        IterativeBackgroundEstimator(jj,:)=min(RMSSignal(jj-...
            FourCyclesHalfDuration,:),Threshold*MovingBackground(jj-...
            FourCyclesHalfDuration,:));
        MovingBackground(jj,:)=MovingBackground(jj-1,:)+...
            (IterativeBackgroundEstimator(jj,:)-...
            IterativeBackgroundEstimator(jj-WindowLength,:))/WindowLength;
    end
    % First detections
    CandidateDetections=(RMSSignal>Threshold*MovingBackground);
    % Find begining and end of detections
    CandidateDetections(1:Offset,:)=false; 
    CandidateDetections(end-Offset:end,:)=false;
    % Keep only detections of enough length
    CandidateDetections=imopen(CandidateDetections,...
        ones(MinimumLength(ii),1)==1);
    % Get event carachteristics
    [IndexSamples,IndexChannels]=find(xor(CandidateDetections(1:end-1,...
        :),CandidateDetections(2:end,:)));
    EventStart=IndexSamples(1:2:end)+1; 
    EventEnd=IndexSamples(2:2:end);
    EventLength=EventEnd-EventStart+1;
    DetectionChannel=IndexChannels(1:2:end);
    NumberOfEvents=length(EventStart); 
    Values=ones(NumberOfEvents,7);
    for jj=1:NumberOfEvents
        Values(jj,:)=[max(RMSSignal(EventStart(jj):EventEnd(jj),...
            DetectionChannel(jj))./MovingBackground(EventStart(jj):...
            EventEnd(jj),DetectionChannel(jj))),...
            max(RMSSignal(EventStart(jj):EventEnd(jj),...
            DetectionChannel(jj))),...
            max(abs(NarrowbandSignal(EventStart(jj):EventEnd(jj),...
            DetectionChannel(jj)))),...
            max(abs(BanspassSignal(EventStart(jj):EventEnd(jj),...
            DetectionChannel(jj)))),...
            max(NarrowbandSignal(EventStart(jj):EventEnd(jj),...
            DetectionChannel(jj))),...
            min(NarrowbandSignal(EventStart(jj):EventEnd(jj),...
            DetectionChannel(jj))),...
            max(abs(diff(Data(EventStart(jj):EventEnd(jj),...
            DetectionChannel(jj)))))];
    end
    % Add detections to Event list
    DetectedEvents=[DetectionChannel SamplingRate*FrequencyBands(ii)*...
        ones(NumberOfEvents,1),EventStart EventLength Values];
    NumberOfEvents=size(DetectedEvents,1);
    Event(EventCounter+(1:NumberOfEvents),:)=DetectedEvents;
    EventCounter=EventCounter+NumberOfEvents;
end
Event=Event(1:EventCounter,:);
event=Event;
% Separate in ripples and fast ripples, join overlapping events
event=[event(:,[1:5 9 10 11]) ones(size(event,1),1)];
Ripples=zeros(EventCounter,9);
FastRipples=Ripples;
RippleCounter=0; FastRippleCounter=0;
% Ripples
for ChannelNumber=1:NumberOfChannels
    EventsInChannel=event(event(:,1)==ChannelNumber&event(:,2)<250,:);
    ChannelEvent=zeros(size(EventsInChannel,1),9);
    Counter=0;
    while size(EventsInChannel,1)>0
        N=size(EventsInChannel,1);
        AllEvents=[EventsInChannel;ChannelEvent(1:Counter,:)];
        Counter=Counter+1;
        IndexOfEvents=AllEvents(:,3)+AllEvents(:,4)+...
            MinimumSeparationRipple>EventsInChannel(1,3)&AllEvents(:,3)...
            <EventsInChannel(1,3)+EventsInChannel(1,4)+MinimumSeparationRipple;
        OverlappingEvents=AllEvents(IndexOfEvents,:);
        EventsInChannel(IndexOfEvents(1:N),:)=[];
        ChannelEvent(IndexOfEvents(N+1:end),:)=[];
        Counter=Counter-nnz(IndexOfEvents(N+1:end));
        ChannelEvent(Counter,:)=[OverlappingEvents(1,1),...
            mean(OverlappingEvents(:,2)) min(OverlappingEvents(:,3)),...
            max(OverlappingEvents(:,3)+OverlappingEvents(:,4))-...
            min(OverlappingEvents(:,3)) max(OverlappingEvents(:,5)),...
            max(OverlappingEvents(:,6)) min(OverlappingEvents(:,7)),...
            max(OverlappingEvents(:,8),[],1) sum(OverlappingEvents(:,9))];
    end
    ChannelEvent=ChannelEvent(1:Counter,:);
    Ripples(RippleCounter+(1:size(ChannelEvent,1)),:)=ChannelEvent;
    RippleCounter=RippleCounter+size(ChannelEvent,1);
end
% Fast ripples
for ChannelNumber=1:NumberOfChannels
    EventsInChannel=event(event(:,1)==ChannelNumber&event(:,2)>250,:);
    ChannelEvent=zeros(size(EventsInChannel,1),9);
    Counter=0;
    while size(EventsInChannel,1)>0
        N=size(EventsInChannel,1);
        AllEvents=[EventsInChannel;ChannelEvent(1:Counter,:)];
        Counter=Counter+1;
        IndexOfEvents=AllEvents(:,3)+AllEvents(:,4)+...
            MinimumSeparation>EventsInChannel(1,3)&AllEvents(:,3)...
            <EventsInChannel(1,3)+EventsInChannel(1,4)+MinimumSeparation;
        OverlappingEvents=AllEvents(IndexOfEvents,:);
        EventsInChannel(IndexOfEvents(1:N),:)=[];
        ChannelEvent(IndexOfEvents(N+1:end),:)=[];
        Counter=Counter-nnz(IndexOfEvents(N+1:end));
        ChannelEvent(Counter,:)=[OverlappingEvents(1,1),...
            mean(OverlappingEvents(:,2)) min(OverlappingEvents(:,3)),...
            max(OverlappingEvents(:,3)+OverlappingEvents(:,4))-...
            min(OverlappingEvents(:,3)) max(OverlappingEvents(:,5)),...
            max(OverlappingEvents(:,6)) min(OverlappingEvents(:,7)),...
            max(OverlappingEvents(:,8),[],1) sum(OverlappingEvents(:,9))];
    end
    ChannelEvent=ChannelEvent(1:Counter,:);
    FastRipples(FastRippleCounter+(1:size(ChannelEvent,1)),:)=ChannelEvent;
    FastRippleCounter=FastRippleCounter+size(ChannelEvent,1);
end
Ripples=Ripples(1:RippleCounter,:);
FastRipples=FastRipples(1:FastRippleCounter,:);
% Compute rates
RippleRate=zeros(1,NumberOfChannels); 
FastRippleRate=RippleRate;
for ChannelNumber=1:NumberOfChannels
    RippleRate(ChannelNumber)=nnz(Ripples(:,1)==ChannelNumber);
    FastRippleRate(ChannelNumber)=nnz(FastRipples(:,1)==ChannelNumber);
end
RippleRate=RippleRate/Duration;
FastRippleRate=FastRippleRate/Duration;

end