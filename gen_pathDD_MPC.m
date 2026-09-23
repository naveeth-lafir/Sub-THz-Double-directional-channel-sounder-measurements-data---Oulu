function pathData = gen_pathDD_MPC(freqBand, scenario, dataRoot)
% gen_pathDD_MPC  Load MPC .mat file for given band & scenario and convert
%                 it to pathData format used by the MIMO channel code.
%
%   pathData = gen_pathDD_MPC(freqBand, scenario)
%   pathData = gen_pathDD_MPC(freqBand, scenario, dataRoot)
%
%   freqBand : 234 or 318  (GHz)
%   scenario : 'Fablab', 'Saalasti_Hall', or 'Storage_Hall'
%   dataRoot : (optional) folder where 234GHz / 318GHz live.
%              Default = current folder (pwd).
%
%   OUTPUT (per link i):
%     pathData{i}.Npaths                   % No of MPCs
%     pathData{i}.TxCoord, .RxCoord
%     pathData{i}.specPaths_UsedDyR.power   [1 x Npaths]  % Rx pow/gain(dB)
%     pathData{i}.specPaths_UsedDyR.delay   [1 x Npaths]  % delay
%     pathData{i}.specPaths_UsedDyR.TxPhi   [1 x Npaths]  % Tx Elevation(90)
%     pathData{i}.specPaths_UsedDyR.RxPhi   [1 x Npaths]  (deg)  ← AoD
%     pathData{i}.specPaths_UsedDyR.TxTheta [1 x Npaths]  (deg)  ← Rx elevation
%     pathData{i}.specPaths_UsedDyR.RxTheta [1 x Npaths]  (deg)  ← Tx elevation
%     pathData{i}.specPaths_UsedDyR.TxScatLoc [] %
%     pathData{i}.specPaths_UsedDyR.RxScatLoc [] % Not available in the data  

    %% --------------------------------------------------------------------
    % 0) Default dataRoot
    % ---------------------------------------------------------------------
    if nargin < 3 || isempty(dataRoot)
        dataRoot = pwd;   % use current directory by default
    end

    %% --------------------------------------------------------------------
    % 1) Resolve band folder from freqBand
    % ---------------------------------------------------------------------
    if isnumeric(freqBand)
        f = freqBand;
    else
        f = str2double(freqBand);
    end

    switch f
        case 234
            bandFolder = '234GHz';
        case 318
            bandFolder = '318GHz';
        otherwise
            error('freqBand must be 234 or 318 (got %g).', f);
    end

    %% --------------------------------------------------------------------
    % 2) Resolve base filename from scenario
    % ---------------------------------------------------------------------
    scenLower = lower(strtrim(scenario));

    switch scenLower
        case {'fablab','fab_lab'}
            baseName = sprintf('Multipath_%dGHz_Fab_lab', f);
        case {'saalasti','saalasti_hall','saalstinsali'}
            baseName = sprintf('Multipath_%dGHz_Saalasti_Hall', f);
        case {'storage','storage_hall'}
            baseName = sprintf('Multipath_%dGHz_Storage_Hall', f);
        otherwise
            error('Unknown scenario "%s". Use Fablab, Saalasti_Hall or Storage_Hall.', scenario);
    end

    matFolder = fullfile(dataRoot, bandFolder);

    % Look for any file that starts with baseName and ends in .mat
    files = dir(fullfile(matFolder, [baseName '*.mat']));

    if isempty(files)
        fprintf('DEBUG: expected something like %s*.mat in %s\n', baseName, matFolder);
        disp('DEBUG: folder contents:');
        disp({dir(matFolder).name}');
        error('No .mat file found matching baseName "%s" in folder %s', baseName, matFolder);
    end

    matFile = fullfile(matFolder, files(1).name);
    fprintf('Using file: %s\n', matFile);

    %% --------------------------------------------------------------------
    % 3) Load RT data from .mat
    % ---------------------------------------------------------------------
    S = load(matFile);

    % Struct data : RTData
    if isfield(S, 'RTData')
        RTdata = S.RTData;
        fprintf('Using variable "RTData"\n');
    else
        % checking struct that has Multipath or RTpaths
        varNames = fieldnames(S);
        RTdata = [];

        for k = 1:numel(varNames)
            V = S.(varNames{k});
            if isstruct(V)
                if isfield(V, 'Multipath') || isfield(V, 'RTpaths')
                    RTdata = V;
                    fprintf('Using variable "%s"\n', varNames{k});
                    break;
                end
            end
        end

        if isempty(RTdata)
            error('File %s does not contain RTData or a struct with Multipath/RTpaths.', matFile);
        end
    end


%% 4) Use RTData to organize data 

Nlinks = numel(RTdata);
pathData = cell(1, Nlinks);

for iL = 1:Nlinks
    L = RTdata(iL);

    % 4a) Paths struct (RTpaths or Multipath)
    if isfield(L,'RTpaths')
        P = L.RTpaths;
    elseif isfield(L,'Multipath')
        P = L.Multipath;
    else
        warning('Link %d: no RTpaths or Multipath field.', iL);
        pathData{iL}.Npaths = NaN;
        continue;
    end

    if isempty(P)
        pathData{iL}.Npaths = NaN;
        continue;
    end

    % keep only valid paths (non-NaN gain)
    gains = [P.gain];
    valid = ~isnan(gains);
    P = P(valid);
    Np = numel(P);

    if Np == 0
        pathData{iL}.Npaths = NaN;
        continue;
    end

    % 4b) Basic info
    pathData{iL}.Npaths  = Np;
    pathData{iL}.TxCoord = L.TxCoord;
    pathData{iL}.RxCoord = L.RxCoord;

    % 4c) Power and delay
    pathData{iL}.specPaths_UsedDyR.power = [P.gain];   % [dB]
    pathData{iL}.specPaths_UsedDyR.delay = [P.del];    % unit = whatever is in .del

    % 4d) Angles
    pathData{iL}.specPaths_UsedDyR.TxTheta = [P.TxTheta];   % azimuth
    pathData{iL}.specPaths_UsedDyR.RxTheta = [P.RxTheta];   % azimuth
    pathData{iL}.specPaths_UsedDyR.TxPhi   = [P.TxPhi];     % elevation
    pathData{iL}.specPaths_UsedDyR.RxPhi   = [P.RxPhi];     % elevation

    % optional: replace missing elevations with 0°
    TxPhi = pathData{iL}.specPaths_UsedDyR.TxPhi;
    RxPhi = pathData{iL}.specPaths_UsedDyR.RxPhi;
    TxPhi(isnan(TxPhi)) = 0;
    RxPhi(isnan(RxPhi)) = 0;
    pathData{iL}.specPaths_UsedDyR.TxPhi = TxPhi;
    pathData{iL}.specPaths_UsedDyR.RxPhi = RxPhi;

    % 4e) Scatter coordinates not available
    pathData{iL}.specPaths_UsedDyR.TxScatLoc = [];
    pathData{iL}.specPaths_UsedDyR.RxScatLoc = [];
end

