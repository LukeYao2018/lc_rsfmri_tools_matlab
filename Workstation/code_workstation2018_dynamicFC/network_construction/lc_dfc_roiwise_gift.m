function lc_dfc_roiwise_gift(all_subjects_path, outputdir, ...
                             TR, volume, numroi, ...
                             window_length, window_step, window_alpha,...
                             numOfSess, doDespike, tc_filter, method, num_repetitions, prefix)
% Modified from GIFT. Users must cite the GIFT software.
% Used to calculate roi-wise dynamic fc using sliding-window method.
% Inputs:
%   input_params have the following fields:
%       all_subjects_path: all subjects' files (wich abslute path). Each subject's file indicates a group of time series with (number of time series) * (number of nodes)
% 	    outputdir: directiory for saving results.
% 	    TR = 2: Time of Repeat.
% 	    volume: How many frames.
% 	    numroi: How many ROI/Node.
%       window_step: sliding-window step.
%       window_length: sliding-window length.
%       window_type: e.g., Gaussian window.
%       window_alpha: Gaussian window alpha, e.g., 3TRs.
% 	    numOfSess: number of sessions.
% 	    doDespike: if despiking.
% 	    tc_filter: if filter.
% 	    method: Using L1 regularisation or not.
% 	    num_repetitions: number of repetitions of random centroid.
% 	    prefix: Results name prefix.
% output
%   zDynamicFC: dynamic FC matrix with Fisher r-to-z transformed; size=N*N*W, 
% 	N is the number of ROIs, W is the number of sliding-window
% Author:  Li Chao
% Email:lichao19870617@gmail.com OR lichao19870617@163.com

%% ----------------------------------input---------------------------------
% ROI signals
% all_subjects_dir = uigetdir(pwd, 'select directory that containing all subjects'' data');
% all_subjects_struct = dir(all_subjects_dir);
% folder = {all_subjects_struct.folder};
% file_name = {all_subjects_struct.file_name}';
% file_name = file_name(3:end);
% all_subjects_path = cell(length(name),1);
% for i =1:length(name)
%     all_subjects_path {i}=fullfile(folder{i},name{i});
% end

% % Out directory saving results
% outputdir = uigetdir(pwd, 'select directory that saving results');

% % Other inputs
% TR = 2;
% volume = 190;
% numroi = 114;
% window_length = 17;
% window_step = 1;
% window_alpha = 3;  % gaussian window alpha
% numOfSess = 1;
% doDespike = 'no';
% tc_filter = 0;
% method = 'L1';
% num_repetitions = 10;
% prefix = '';
%% -------------------------------------------------------------------

%% Make result directory
result_dir_of_dynamic = fullfile(outputdir, strcat('zDynamicFC_WindowLength',num2str(window_length),'_WindowStep',num2str(window_step)));
if ~exist(result_dir_of_dynamic, 'dir')
    mkdir(result_dir_of_dynamic);
end

%% ----------------------------Run------------------------------------
% Load timeseries
tic;
numOfSub = length(all_subjects_path);
tc = zeros(numOfSub, numOfSess, volume, numroi);
for i = 1:numOfSub
   tc(i, 1,:,:) = importdata(all_subjects_path{i});
end

% Make sliding window
c = icatb_compute_sliding_window(volume, window_alpha, window_length);
A = repmat(c, 1, numroi);
Nwin = volume - window_length;

% Initial_lambdas
initial_lambdas = (0.1:.03:.40);
best_lambda = zeros(1, numOfSub);
outFiles = cell(1, numOfSub);
dataSetCount = 0;

% Loop over subjects
for nSub = 1:numOfSub
    % Loop over sessions
    for nSess = 1:numOfSess
        dataSetCount = dataSetCount + 1;
        results_file = [prefix, name{nSub}];
        FNCdyn = zeros(Nwin, numroi*(numroi - 1)/2);
        Lambdas = zeros(num_repetitions, length(initial_lambdas));
        disp(['Computing dynamic FNC on subject ', num2str(nSub), ' session ', num2str(nSess)]);
        
        if (strcmpi(doDespike, 'yes') && (tc_filter > 0))
            disp('Despiking and filtering timecourses ...');
        elseif (strcmpi(doDespike, 'yes') && (tc_filter == 0))
            disp('Despiking timecourses ...');
        elseif (strcmpi(doDespike, 'no') && (tc_filter > 0))
            disp('Filtering timecourses ...');
        end
        
        % Preprocess timecourses
        for nComp = 1:numroi
            current_tc = squeeze(tc(nSub, nSess, :, nComp));
            % Despiking timecourses
            if (strcmpi(doDespike, 'yes'))
                current_tc = icatb_despike_tc(current_tc, TR);
            end
            
            % Filter timecourses
            if (tc_filter > 0)
                current_tc = icatb_filt_data(current_tc, TR, tc_filter);
            end
            tc(nSub, nSess, :, nComp) = current_tc;
        end
        
        % Apply circular shift to timecourses
        tcwin = zeros(Nwin, volume, numroi);
        for ii = 1:Nwin
            Ashift = circshift(A, round(-volume/2) + round(window_length/2) + ii);
            tcwin(ii, :, :) = squeeze(tc(nSub, nSess, :, :)).*Ashift;
        end
        
        if strcmpi(method, 'L1')
            useMEX = 0;
            try
                GraphicalLassoPath([1, 0; 0, 1], 0.1);
                useMEX = 1;
            catch
            end
            
            disp('Using L1 regularisation ...');
            
            % L1 regularisation
            Pdyn = zeros(Nwin, numroi*(numroi - 1)/2);
            
            fprintf('\t rep ')
            % Loop over no of repetitions
            for r = 1:num_repetitions
                fprintf('%d, ', r)
                [traivolumeC, testTC] = split_timewindows(tcwin, 1);
                traivolumeC = icatb_zscore(traivolumeC);
                testTC = icatb_zscore(testTC);
                [wList, thetaList] = computeGlasso(traivolumeC, initial_lambdas, useMEX);
                obs_cov = icatb_cov(testTC);
                L = cov_likelihood(obs_cov, thetaList);
                Lambdas(r, :) = L;
            end
            
            fprintf('\n')
            [mv, minIND] =min(Lambdas, [], 2);
            blambda = mean(initial_lambdas(minIND));
            fprintf('\tBest Lambda: %0.3f\n', blambda)
            best_lambda(dataSetCount) = blambda;
            
            % now actually compute the covariance matrix
            fprintf('\tWorking on estimating covariance matrix for each time window...\n')
            for ii = 1:Nwin
                %fprintf('\tWorking on window %d of %d\n', ii, Nwin)
                [wList, thetaList] = computeGlasso(icatb_zscore(squeeze(tcwin(ii, :, :))), blambda, useMEX);
                a = icatb_corrcov(wList);
                a = a - eye(numroi);
                FNCdyn(ii, :) = lc_mat2vec(a);
                % InvC = -thetaList;
                % r = (InvC ./ repmat(sqrt(abs(diag(InvC))), 1, numroi)) ./ repmat(sqrt(abs(diag(InvC)))', numroi, 1);
                % r = r + eye(numroi);
                % Pdyn(ii, :) = lc_mat2vec(r);
            end
            
            FNCdyn = atanh(FNCdyn);
            FNCdyn = lc_vec2mat(FNCdyn,numroi);
            disp(['.... saving file ', results_file]);
            % icatb_save(fullfile(result_dir_of_dynamic, results_file), 'Pdyn', 'Lambdas', 'FNCdyn');
            icatb_save(fullfile(result_dir_of_dynamic, results_file), 'FNCdyn');  % Discard saving Pdyn and Lambdas
            
        elseif strcmpi(method, 'none')
            % No L1
            for ii = 1:Nwin
                a = icatb_corr(squeeze(tcwin(ii, :, :)));
                [FNCdyn(ii, :), ind] = lc_mat2vec(a);
            end
            FNCdyn = atanh(FNCdyn);
            FNCdyn = lc_vec2mat(FNCdyn,numroi);
            
            disp(['.... saving file ', results_file]);
            save(fullfile(result_dir_of_dynamic, results_file), 'FNCdyn');
        end
        
        outFiles{dataSetCount} = results_file;
        disp('Done');
        fprintf('\n');
        
    end
    % End of loop over sessions
end
% End of loop over subjects

% dfc_info.best_lambda = best_lambda;
% dfc_info.outputFiles = outFiles;
% fileN = fullfile(result_dir_of_dynamic, [prefix,'dfc_info', '.mat']);
% disp(['Saving parameter file ', fileN, ' ...']);
% save(fileN,'dfc_info')
totalTime = toc;

fprintf('\n');
disp('Analysis Complete');
disp(['Total time taken to complete the analysis is ', num2str(totalTime/60), ' minutes']);
diary('off');
fprintf('\n');


%% -------------------------------Utility Functions-------------------------------
function [trainTC, testTC] = split_timewindows(TCwin, ntrain)
[Nwin, nT, nC] = size(TCwin);
r = randperm(Nwin);
trainTC = TCwin(r(1:ntrain),:,:);
testTC = TCwin(r(ntrain+1:end),:,:);
trainTC = reshape(trainTC, ntrain*nT, nC);
testTC = reshape(testTC, (Nwin-ntrain)*nT, nC);

function mat = lc_vec2mat(dfc_2d, numroi)
n_feature = size(dfc_2d, 1);
mat = zeros(numroi, numroi, n_feature);
for i = 1:n_feature
    mat(:,:,i) = vec2mat(dfc_2d(i,:),numroi);
end

function mat = vec2mat(vec,numroi)
temp = ones(numroi, numroi);
mat = zeros(numroi, numroi);
ind = triu(temp,1) == 1;
mat(ind) = vec;
mat = mat + mat';


function [vec, ind] = lc_mat2vec(mat)
% vec = mat2vec(mat)
% returns the lower triangle of mat
% mat should be square
% Revised by Li Chao
[n,m] = size(mat);
if n ~=m
    error('mat must be square!')
end
temp = ones(n);
%% find the indices of the upper triangle of the matrix
ind = triu(temp, 1) == 1;
vec = mat(ind);


function c = icatb_compute_sliding_window(nT, win_alpha, wsize)
% Compute sliding window
% Thanks to GIFT software
nT1 = nT;
if mod(nT, 2) ~= 0
    nT = nT + 1;
end
m = nT/2;
w = round(wsize/2);
gw = gaussianwindow(nT, m, win_alpha);
b = zeros(nT, 1);  b((m -w + 1):(m+w)) = 1;
c = conv(gw, b); c = c/max(c); c = c(m+1:end-m+1);
c = c(1:nT1);

function w = gaussianwindow(N,x0,sigma)
x = 0:N-1;
w = exp(- ((x-x0).^2)/ (2 * sigma * sigma))';

function L = cov_likelihood(obs_cov, theta)
% L = cov_likelihood(obs_cov, sigma)
% INPUT:
% obs_cov is the observed covariance matrix
% theta is the model precision matrix (inverse covariance matrix)
% theta can be [N x N x p], where p lambdas were used
% OUTPUT:
% L is the negative log-likelihood of observing the data under the model
% which we would like to minimize
nmodels = size(theta,3);
L = zeros(1,nmodels);
for ii = 1:nmodels
    % log likelihood
    theta_ii = squeeze(theta(:,:,ii));
    L(ii) = -log(det(theta_ii)) + trace(theta_ii*obs_cov);
end

function [wList, thetaList] = computeGlasso(tc, initial_lambdas, useMEX)
% Compute graphical lasso
if (useMEX == 1)
    [wList, thetaList] = GraphicalLassoPath(tc, initial_lambdas);
else
    tol = 1e-4;
    maxIter = 1e4;
    S = icatb_cov(tc);
    thetaList = zeros(size(S, 1), size(S, 2), length(initial_lambdas));
    wList = thetaList;
    
    for nL = 1:size(wList, 3)
        [thetaList(:, :, nL), wList(:, :, nL)] = icatb_graphicalLasso(S, initial_lambdas(nL), maxIter, tol);
    end
end