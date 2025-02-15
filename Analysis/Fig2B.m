%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Con_num - EEG: pca all electrodes
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% LOAD DATA

clc
clear

% Paths
eegfolder           = 'EEG_ERP';
savefolder          = 'EEG_ERP';

% Load stuff
Load_paths_and_data; % load data and path
Config_plot; % load plot variables

% Logicals
do.pca          = true; % run pca?
do.save_comp    = true; % save pca results?

do.plotting     = true; % plot?
do.smooth       = false; % smooth results?
do.signif       = false; % test significance?
do.save_plot    = false; % save plot?

%% Extra variables needed for analysis

% Code for target (fill, primary, secondary)
data.target         = round(data.ctg);

data.dist2targ      = 0.*data.target;
data.dist2targ(1)   = data.num(1);
primtg              = data.num(1);

for t = 2:params.ttrials
    
    if data.block(t) ~= data.block(t-1) % if first trial
        primtg = 0;
        data.dist2targ(t) = 0;
    else
        data.dist2targ(t) = data.num(t) - primtg;
    end
    
    if data.target(t) == 1
        primtg = data.num(t);
    end
end

data.dist2targ(data.ctg == 1) = 0;

% Adjacent primary targets
data.comppair   = 0*[data.sub data.sub];

for t = 1:params.ttrials
    if data.ctg(t) == 1
        data.comppair(t,1)  = 0;
        data.comppair(t,2)  = 0;
        last_prim           = data.num(t);
    elseif data.ctg(t) > 1 && data.ctg(t) < 2
        data.comppair(t,1)  = last_prim;
        data.comppair(t,2)  = data.num(t);
        last_prim           = data.comppair(t,2);
    else
        data.comppair(t,1)  = last_prim;
        data.comppair(t,2)  = data.num(t);
    end
end

% Get midpoint of range
data.rangemidpoint = data.mod*0;
for c = 1:params.nconds
    idx = data.mod == c;
    data.rangemidpoint(idx) = median(params.condnumz{c});
end

% Distance to midpoint of range
data.dist2mid       = 0*data.num;
data.dist2mid_prev  = 0*data.num;

idx = data.ctg == 1.1 | data.ctg == 1.2;
data.dist2mid(idx)      = abs(data.num(idx) - data.rangemidpoint(idx));
data.dist2mid_prev(idx) = abs(data.comppair(idx,1) - data.rangemidpoint(idx));

% Distance to midpoint of full range
data.dist2fullmid_curr  = 0*data.num;
data.dist2fullmid_prev  = 0*data.num;

idx = data.ctg == 1.1 | data.ctg == 1.2;
data.dist2fullmid_curr(idx)     = abs(data.num(idx) - median(params.condnumz{3}));
data.dist2fullmid_prev(idx)     = abs(data.comppair(idx,1) - median(params.condnumz{3}));

% Visual dissimilarity
params.num = 25:40;
load('Vis_sim_numbers'); % load visual dissimilarity between numbers
tmpvis      = squareform(visSim);
data.vissim = 0*data.sub;

for t = 1:params.ttrials
    if data.comppair(t,1) ~= 0
        ind1 = params.num == data.comppair(t,1);
        ind2 = params.num == data.comppair(t,2);
        data.vissim(t) = tmpvis(ind1,ind2);
    end
end

% Find outlying RT trials
boundval    = 2.5;
outRT       = zeros(params.nsubj,2);
inv_rt      = 1./data.RT;
for s = 1:params.nsubj
    mRT         = mean(inv_rt(data.RT > 0 & data.sub == params.submat(s)));
    sdRT        = std(inv_rt(data.RT > 0 & data.sub == params.submat(s)));
    outRT(s,1)  = mRT-boundval*sdRT; % lower bound outliers RT
    outRT(s,2)  = mRT+boundval*sdRT; % upper bound outliers RT
end

%% PCA

% Some settings
params.whichTarget  = 1;
targetname          = {'fill','prim','sec'};

ntimepoints         = length(timepoints); % Number of timepoints
nchan               = 60; % number of electrodes
ncomp               = 43; % 90% variance explained (median 42, mean 43)
pcomp               = zeros(params.nsubj,ntimepoints,ncomp);
X                   = [];

filename            = sprintf('PCA_%s_%dcomp_allelec',targetname{params.whichTarget+1},ncomp);

if do.pca
    
    for s = 1:params.nsubj
        
        fprintf('\nPCA sub %d', params.submat(s));
        
        % File names
        inputfile   = sprintf('Con_numbers_sub%03d',params.submat(s));
        
        % Which trials to use
        idx     = data.sub == params.submat(s);
        orgidx  = data.target(idx) == params.whichTarget & data.ctg(idx) ~= 1 & data.r(idx) > 0;
        
        % Get eeg data
        [erpdata,bindx{s},eindx] = PreprocERP(orgidx,inputfile,paths);
        
        % Get data in right format
        X = erpdata(:,:,eindx);
        X = permute(X,[1,3,2]);
        X = reshape(X,[size(X,1)*size(X,2),size(X,3)]);
        
        % PCA
        [pcomp(s,:,:), loadings{s}] = pca(X-mean(X),'NumComponents',ncomp);
        
    end
    
    pc_flip     = pcomp;
    load_flip   = loadings;
    
    % Save pc and loadings?
    if do.save_comp
        save(fullfile(paths.data.saveEEG,filename),'pc_flip','load_flip','bindx');
        fprintf('\n%s saved.\n',filename);
    end
    
else
    load(fullfile(paths.data.saveEEG,filename));
end

%% Regression on reconstructed data

clear Betas

x1 = data.num;
x2 = abs(data.dist2targ);
x3 = sum(data.comppair,2);
x4 = data.RT;
x5 = data.vissim;
x6 = data.comppair(:,1);
x7 = data.dist2mid;
x8 = data.dist2mid_prev;
x9 = data.dist2fullmid_curr;
x10 = data.dist2fullmid_prev;

regr        = [x1 x2 x4 x5 x9 x10];
regrnamez   = {'Numerical magnitude','|\Delta|_{p}','RT','vissim','|\Delta M|_{c}','|\Delta M|_{p}'};
whichComp   = [1:ncomp];

for s = 1:params.nsubj
    
    fprintf('\n Regression sub %d\n',s);
    
    % Reconstruct eeg data
    tmpY        = load_flip{s};
    reconEEG    = tmpY(:,whichComp)*squeeze(pc_flip(s,:,whichComp))';
    finalY      = reshape(reconEEG,[nchan,sum(bindx{s}),size(reconEEG,2)]);
    
    idx         = data.sub == params.submat(s);
    regr2       = regr(idx,:);
    finalX      = [1+regr(bindx{s},1)*0 zscore(regr2(bindx{s},:))]; % add intercept
    
    for t = 1:ntimepoints
        for e = 1:nchan
            Betas(s,:,e,t) = regress(squeeze(finalY(e,:,t))',finalX);
        end
    end
end


%% Plot regression results

if do.plotting
        
    regrnamez = {'magn','absdist','rt','vissim','dist2mid_c','dist2mid_p'};
    
    whichRegr   = 6;
    timelims    = 200:50:350;
    ntimebins   = length(timelims)-1;
    p_crit      = 0.05;
    maplims     = [-4 4];
    
    for b = 1:ntimebins
        
        timeidx     = timepoints >= timelims(b) & timepoints < timelims(b+1);
        subdat      = squeeze(mean(Betas(:,whichRegr,:,timeidx),4));
        tdat        = ttransform(subdat);
        
        pval        = 2 * tcdf(-abs(tdat), params.nsubj-1);
        pFDR        = mafdr(pval,'BHFDR',true); % FDR correction
        pmask       = pFDR <= p_crit;
        
        eggheadplot('Channels', {chanlocs.labels}, 'Amplitude', tdat, 'Method', 'natural',...
            'Scale', maplims, 'Contours',0, 'FillColor', [1 1 1], 'MapStyle', 'jet', 'Style', 'Full', 'ElectrodeSize', 10, 'ShowBrain','No','Smooth',50);
        axis equal
        
        % Set color map
        nsteps = 101;
        colidx = logical(1-(abs(linspace(maplims(1),maplims(2),nsteps)) > tinv(1-p_crit,params.nsubj-1)));
        ct = flipud(cbrewer('div', 'RdBu', nsteps));
        ct(colidx,:) = repmat([1 1 1],sum(colidx),1);
        colormap(ct);
        
        if do.save_plot
            tp1 = timelims(b);
            tp2 = timelims(b+1);
            save2tiff(gcf,paths.figures.current,sprintf('Topo_%s_%s_%d-%dms',targetname{params.whichTarget+1},regrnamez{whichRegr-1},tp1,tp2),[.1 .1 400 300]);
        end
    end
    
    do.save_plot = false;
    
    % Colorbar
    
    figure;
    
    hC = colorbar('horizontal');
    caxis(maplims);
    
    % Set color map
    nsteps = 101;
    colidx = logical(1-(abs(linspace(maplims(1),maplims(2),nsteps)) > tinv(1-p_crit,params.nsubj-1)));
    ct = flipud(cbrewer('div', 'RdBu', nsteps));
    ct(colidx,:) = repmat([1 1 1],sum(colidx),1);
    colormap(ct);
    
    ax = gca;
    set(hC,'FontSize',24,'YTick',[maplims(1),0,maplims(2)],'YTickLabel',{num2str(maplims(1)),'non-sig',num2str(maplims(2))});
    
    if do.save_plot
        save2tiff(gcf,paths.figures.current,sprintf('Colorbar_tval_nonsig_%d-%d',maplims(1),maplims(2)),[.1 .1 400 300]);
    end
    
end
