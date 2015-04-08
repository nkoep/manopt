function [Y, infos, problem_description] =  low_rank_dist_completion(problem_description)
% Perform low-rank distance matrix completion w/ automatic rank detection.
%
% function Y = low_rank_dist_completion(problem_description)
% function [Y, infos, out_problem_description] = low_rank_dist_completion(problem_description)
%
% It implements the ideas of Journée, Bach, Absil and Sepulchre, SIOPT, 2010,
% applied to the problem of low-rank Euclidean distance matrix completion.
% The details are in the paper "Low-rank optimization for distance matrix completion",
% B. Mishra, G. Meyer, and R. Sepulchre, IEEE CDC, 2011.
%
% Paper link: http://arxiv.org/abs/1304.6663.
%
% Input:
% -------
%
% problem_description: The problem structure with the description of the problem.
%
%
% - problem_description.data_train: Data structure for known distances that are used to learn a low-rank model.
%                                   It contains the 3 fields that are shown
%                                   below. An empty "data_train" structure
%                                   will generate the 3d Helix instance
%
%       -- data_train.entries:      A column vector consisting of known
%                                   distances. An empty "data_train.entries"
%                                   field will generate the 3d Helix
%                                   instance.
%
%       -- data_train.rows:         The row position of th corresponding
%                                   distances. An empty "data_train.rows"
%                                   field will generate the 3d Helix
%                                   instance.
%
%       -- data_train.cols:         The column position of th corresponding
%                                   distances. An empty "data_train.cols"
%                                   field will generate the 3d Helix
%                                   instance.
%
%
%
% - problem_description.data_test:  Data structure to compute distances for the "unknown" (to the algorithm) distances.
%                                   It contains the 3 fields that are shown
%                                   below. An empty "data_test" structure
%                                   will not compute the test error.
%
%       -- data_test.entries:       A column vector consisting of "unknown" (to the algorithm)
%                                   distances. An empty "data_test.entries"
%                                   field will not compute the test error.
%       -- data_test.rows:          The row position of th corresponding
%                                   distances. An empty "data_test.rows"
%                                   field will not compute the test error.
%       -- data_test.cols:          The column position of th corresponding
%                                   distances. An empty "data_test.cols"
%                                   field will not compute the test error.
%
%
%
% - problem_description.n:          The number of data points. An empty
%                                   "n", but complete "data_train" structure
%                                   will lead to an error, to avoid
%                                   potential data inconsistency.
%
%
%
% - problem_description.fixedrank_algo: Fixed-rank algorithm. Options are
%                                       'TR' for trust-regions,
%                                       'CG' for conjugate gradients,
%                                       'SD' for steepest descent.
%                                       By default, it is 'TR'.
%
%
%
%
% - problem_description.rank_initial: Starting rank. By default, it is 1.
%
%
%
% - problem_description.rank_max:     Maximum rank. By default, it is equal to
%                                     "problem_description.n".
%
%
%
%
% - problem_description.params:  Structure array containing algorithm
%                                parameters for stopping criteria.
%       -- params.abstolcost:    Tolerance on absolute value of cost.
%                                By default, it is 1e-3.
%
%
%       -- params.reltolcost:    Tolerance on absolute value of cost.
%                                By default, it is 1e-3.
%       -- params.tolgradnorm:   Tolerance on the norm of the gradient.
%                                By default, it is 1e-5.
%       -- params.maxiter:       Maximum number of fixe-rank iterations.
%                                By default, it is 100.
%       -- params.tolSmin:       Tolerance on smallest eigenvalue of Sy,
%                                the dual variable.
%                                By default, it is 1e-5.
%       -- params.tolrankdeficiency:   Tolerance on the
%                                      smallest singular value of Y.
%                                      By default, it is 1e-3.
%
%
% Output:
% --------
%
%   Y:                    n-by-r solution matrix of rank r.
%   infos:                Structure array with computed statistics.
%   problem_description:  Structure array with used problem description.
%
%
%
% Please cite the Manopt paper as well as the research paper:
%     @InProceedings{mishra2011dist,
%       Title        = {Low-rank optimization for distance matrix completion},
%       Author       = {Mishra, B. and Meyer, G. and Sepulchre, R.},
%       Booktitle    = {{50th IEEE Conference on Decision and Control}},
%       Year         = {2011},
%       Organization = {{IEEE CDC}}
%     }



% This file is part of Manopt: www.manopt.org.
% Original author: Bamdev Mishra, April 06, 2015.
% Contributors: Nicolas Boumal.
% Change log:


    % Check problem description
    if ~exist('problem_desription', 'var')
        problem_description = struct();
    end
    
    
    problem_description = check_problem_description(problem_description); % Check the problem description;
    
    
    
 
    % Common quantities
    
    data_train = problem_description.data_train;
    data_test =  problem_description.data_test;
    n =  problem_description.n;
    fixedrank_algo =  problem_description.fixedrank_algo;
    rank_initial = problem_description.rank_initial;
    rank_max =  problem_description.rank_max;
    params =  problem_description.params;
    
    
    N = data_train.nentries; % Number of known distances
    EIJ = speye(n);
    EIJ = EIJ(:, data_train.rows) - EIJ(:, data_train.cols);
    
    rr = rank_initial; % Starting rank.
    Y = randn(n, rr); % Random starting initialization.
    
    
    
    
    
    % Information 
    time = [];               % Time for each iteration per rank
    cost = [];               % Cost at each iteration per rank
    test_error = [];         % Test error at each iteration per rank
    rank = [];               % Rank at each iteration
    rank_change_stats = [];  % Some stats relating the change of ranks
    
    
    
    
    
    % Main loop rank search 
    rank_search = 0;
    
    while (rr <= rank_max), % When r = n a global min is attained for sure.
        rank_search = rank_search + 1;
        
        fprintf('>> Rank %d <<\n', rr);
        
        % Follow the descent direction to compute an iterate in a higher dimension
        if (rr > rank_initial),
            if isempty(restartDir), % If no restart dir avail. do a random restart
                
                disp('No restart dir available, random restart is performed');
                Y = randn(n, rr);
                
            else % Perform a simple line-search based on the restart direction
                
                disp('>> Line-search with restart direction');
                Y(:, rr) = 0; % Append a column of zeroes
                
                Z = Y(data_train.rows, :) - Y(data_train.cols,:);
                estimDists = sum(Z.^2, 2);
                errors = (estimDists - data_train.entries);
                
                costBefore = mean(errors.^2);
                fprintf('>> Cost before = %f\n',costBefore);
                
                % A very rough estimate of the inverse of the Lipschitz constant.
                % The "2*sqrt(n)" term comes from the diagonal operation.
<<<<<<< HEAD
                % We multiply the estimate by 4, as its better to have a higher
                % stepsize than a lower one.
=======
                % We multiply the estimate by 4, as it's better to have a higher
                % stepsize than a lower one. 
>>>>>>> b5b2cb7f5f76455f948624b975181141ec1a29d2
                stepsize = 4*(n^2)/((1 + 2*sqrt(n))*N);
                
                linsearch_fail = false;
                for i = 1 : 25, % 25 backtracking to find a descent direction.
                    % Update
                    Y(:,rr) = stepsize*restartDir;
                    
                    % Compute cost
                    Z = Y(data_train.rows, :) - Y(data_train.cols,:);
                    estimDists = sum(Z.^2,2);
                    errors = (estimDists - data_train.entries);
                    
                    costAfter = mean(errors.^2);
                    fprintf('>> Cost after = %f\n',costAfter);
                    
                    % Armijo condition
                    armijo = (costAfter - costBefore) <= 0.5 * stepsize * abs(s_min);
                    
                    if armijo,
                        break;
                    else
                        stepsize = stepsize/2;
                    end
                    
                    if i == 25,
                        linsearch_fail = true;
                    end
                end
                
                % Check for sufficient decrease of the cost function.
                if linsearch_fail...
                        ||(costAfter >= costBefore)...
                        || abs(costAfter - costBefore) < 1e-8,
                    disp('Decrease is not sufficient, random restart');
                    Y = randn(n, rr);
                end
                
            end
            
        end
        
        
        
        
        % Fixed-rank optimization with Manopt
        [Y, infos_fixedrank] = low_rank_dist_completion_fixedrank(fixedrank_algo, data_train, data_test, Y, params);
        
        
        
        % Some info logging
        thistime = [infos_fixedrank.time];
        if ~isempty(time)
            thistime = time(end) + thistime;
        end
        
        time = [time thistime]; %#ok<AGROW>
<<<<<<< HEAD
        cost = [cost [infos_fixedrank.cost]]; %#ok<AGROW>
        rank = [rank [infos_fixedrank.rank]];
        rank_change_stats(rank_search).rank = rr;
        rank_change_stats(rank_search).iter = length([infos_fixedrank.cost]);
        rank_change_stats(rank_search).Y = Y;
=======
        cost = [cost [infos.cost]]; %#ok<AGROW>
        rank = [rank [infos.rank]]; %#ok<AGROW>
        rank_change_stats(rank_search).rank = rr; %#ok<AGROW>
        rank_change_stats(rank_search).iter = length([infos.cost]); %#ok<AGROW>
        rank_change_stats(rank_search).Y = Y; %#ok<AGROW>
>>>>>>> b5b2cb7f5f76455f948624b975181141ec1a29d2
        
        if isfield(infos_fixedrank, 'test_error')
            test_error = [test_error [infos_fixedrank.test_error]]; %#ok<AGROW>
        end
        
        
        
        % Evaluate gradient of the convex cost function (i.e. wrt X).
        Z = Y(data_train.rows, :) - Y(data_train.cols,:);
        estimDists = sum(Z.^2,2);
        errors = (estimDists - data_train.entries);
        
        
        
        
        
        % Dual variable and its minimum eigenvalue that is used to guarantee convergence.
        Sy = EIJ * sparse(1:N,1:N,2 * errors / N,N,N) * EIJ';
        
        
        % Compute smallest algebraic eigenvalue of Sy,
        % this gives us a descent direction for the next rank (v)
        % as well as a way to control progress toward the global
        % optimum (s_min).
        
        % Make eigs silent.
        opts.disp = 0;
        opts.issym = true;
        [v, s_min] = eigs(Sy, 1, 'SA', opts);
        
        
        
        
        
        % Check whether Y is rank deficient.
        vp = svd(Y);
        
        % Stopping criterion.
        fprintf('>> smin = %.3e, and min(vp) = %.3e\n',s_min,min(vp));
        if (s_min  > params.tolSmin) || (min(vp) < params.tolrankdeficiency),
            break;
        end
        
        
        
        % Update rank
        rr = rr + 1;
        
        
        
        % Compute descent direction
        if (s_min < -1e-10),
            restartDir = v;
        else
            restartDir = [];
        end
    end
    
    
    % Collect relevant statistics
    infos.time = time;
    infos.cost = cost;
    infos.rank = rank;
    infos.test_error = test_error;
    infos.rank_change_stats = rank_change_stats;
    
    
    
    % Few plots.
    show_plots(problem_description, infos);
    
end











%%
function localdefaults = getlocaldefaults()
    
    localdefaults.abstolcost = 1e-3;
    localdefaults.reltolcost = 1e-3;
    localdefaults.tolSmin = -1e-3;
    localdefaults.tolrankdeficiency = 1e-3;
    localdefaults.tolgradnorm = 1e-5;
    localdefaults.maxiter = 100;
    
end







%%
function [Yopt, infos] = low_rank_dist_completion_fixedrank(fixedrank_algo, data_train, data_test, Y_initial, params)
    % Common quantities that are used often in the optimization process.
    [n, r] = size(Y_initial);
    EIJ = speye(n);
    EIJ = EIJ(:, data_train.rows) - EIJ(:, data_train.cols);
    
    
    
    % Create the problem structure
    problem.M = symfixedrankYYfactory(n,  r);
    
    
    
    % Cost evaluation
    problem.cost = @cost;
    function [f, store] = cost(Y, store)
        if ~isfield(store, 'xij')
            store.xij = EIJ'*Y;
        end
        xij = store.xij;
        estimDists = sum(xij.^2,2);
        f = 0.5*mean((estimDists - data_train.entries).^2);
    end
    
    
    
    % Gradient evaluation.
    problem.grad = @grad;
    function [g, store] = grad(Y, store)
        N = data_train.nentries;
        if ~isfield(store, 'xij')
            store.xij = EIJ'*Y;
        end
        xij = store.xij;
        estimDists = sum(xij.^2,2);
        g = EIJ * sparse(1:N,1:N,2 * (estimDists - data_train.entries) / N, N, N) * xij;
    end
    
    
    
    % Hessian evaluation.
    problem.hess = @hess;
    function [Hess, store] = hess(Y, eta, store)
        N = data_train.nentries;
        if ~isfield(store, 'xij')
            store.xij = EIJ'*Y;
        end
        xij = store.xij;
        zij = EIJ'*eta;
        estimDists = sum(xij.^2,2);
        crossYZ = 2*sum(xij .* zij,2);
        Hess = (EIJ*sparse(1:N,1:N,2 * (estimDists - data_train.entries) / N,N,N))*zij + (EIJ*sparse(1:N,1:N,2 * crossYZ / N,N,N))*xij;
        Hess = problem.M.proj(Y, Hess);
    end
    
    
    %     % Check numerically whether gradient and Hessian are correct
    %     checkgradient(problem);
    %     drawnow;
    %     pause;
    %     checkhessian(problem);
    %     drawnow;
    %     pause;
    
    
    
    % When asked, ask Manopt to compute the test error at every iteration.
    if ~isempty(data_test)
        options.statsfun = @compute_test_error;
        EIJ_test = speye(n);
        EIJ_test = EIJ_test(:, data_test.rows) - EIJ_test(:, data_test.cols);
    end
    function stats = compute_test_error(problem, Y, stats) %#ok<INUSL>
        xij = EIJ_test'*Y;
        estimDists_test = sum(xij.^2,2);
        stats.test_error = 0.5*mean((estimDists_test - data_test.entries).^2);
        stats.rank = r;
    end
    
    
    
    % Stopping criteria options
    options.stopfun = @mystopfun;
    function stopnow = mystopfun(problem, Y, info, last) %#ok<INUSL>
        stopnow = (last >= 3 && (info(last-2).cost - info(last).cost < params.abstolcost || abs(info(last-2).cost - info(last).cost)/info(last).cost < params.reltolcost));
    end
    options.tolgradnorm = params.tolgradnorm;
    options.maxiter = params.maxiter;
    
    
    
    % Call the appropriate algorithm.
    if strcmp(fixedrank_algo, 'TR'),
        options.solver = @trustregions;
    elseif strcmp(fixedrank_algo, 'CG'),
        options.solver = @conjugategradient;
    elseif strcmp(fixedrank_algo, 'SD'),
        options.solver = @steepestdescent;
    end
    
    
    % Algorithm
    [Yopt, ~, infos] = manoptsolve(problem, Y_initial, options);
    
    
end






%%
function problem_description = get_3d_Helix_instance()
    
    % Helix curve in 3d
    tvec = 0:2*pi/100:2*pi;
    tvec = tvec'; % column vector
    xvec = 4*cos(3*tvec);
    yvec = 4*sin(3*tvec);
    zvec = 2*tvec;
    Yo = [xvec, yvec, zvec];
    n = size(Yo, 1); % Number of points
    
    % Fraction of unknown distances
    fractionOfUnknown = 0.85;
    
    % True distances among points in 3d Helix
    trueDists = pdist(Yo)'.^2; % True distances
    
    
    % Add noise (set noise_level = 0 for clean measurements)
    noise_level = 0; % 0.01;
    trueDists = trueDists + noise_level * std(trueDists) * randn(size(trueDists));
    
    
    % Compute all pairs of indices
    H = tril(true(n), -1);
    [I, J] = ind2sub([n, n], find(H(:)));
    clear 'H';
    
    
    % Train data
    train = false(length(trueDists), 1);
    train(1:floor(length(trueDists)*(1- fractionOfUnknown))) = true;
    train = train(randperm(length(train)));
    
    data_train.rows = I(train);
    data_train.cols = J(train);
    data_train.entries = trueDists(train);
    data_train.nentries = length(data_train.entries);
    
    
    % Test data
    data_test.nentries = 1*data_train.nentries; % Depends how big data that we can handle.
    test = false(length(trueDists),1);
    test(1 : floor(data_test.nentries)) = true;
    test = test(randperm(length(test)));
    data_test.rows = I(test);
    data_test.cols = J(test);
    data_test.entries = trueDists(test);
    
    
    % Fixed-rank algorithm
    fixedrank_algo = 'TR'; % Trust-regions
    
    
    % Rank bounds
    rank_initial = 1; % Starting rank
    rank_max = n; % Maximum rank
    
    
    % Basic parameters used in optimization
    params = struct();
    params = mergeOptions(getlocaldefaults, params);
    
    
    % Problem description
    problem_description.data_train = data_train;
    problem_description.data_test = data_test;
    problem_description.n = n;
    problem_description.fixedrank_algo = fixedrank_algo;
    problem_description.rank_initial = rank_initial;
    problem_description.rank_max = rank_max;
    problem_description.params = params;
    problem_description.Yo = Yo; % Used for plots
end





%%
function checked_problem_description = check_problem_description(problem_description)
    checked_problem_description = problem_description;
    
    % Check train data
    if ~isempty(problem_description)...
            || ~all(isfield(problem_description,{'data_train'}) == 1)...
            || ~all(isfield(problem_description.data_train,{'cols', 'rows', 'entries'}) == 1)...
            || isempty(problem_description.data_train.cols)...
            || isempty(problem_description.data_train.rows)...
            || isempty(problem_description.data_train.entries)
        
        warning('low_rank_dist_completion:problem_description', ...
            'The training set is not properly defined. We work with the default 3d Helix example.\n');
        checked_problem_description = get_3d_Helix_instance();
        checked_problem_description.helix_example = true;
        return; % No need to check further.
    end
    
    
    % Check number of data points
    if ~isfield(problem_description, 'n')
        error('low_rank_dist_completion:problem_description',...
            'Error. The scalar corresponding to field "n" of problem description must be given. \n');
    end
    
    
    
    % Check fixed-rank algorithm to use
    if isfield(problem_description, 'fixedrank_algo')
        fixedrank_algo = problem_description.fixedrank_algo;
        if ~(strcmp(fixedrank_algo, 'TR')...
                || strcmp(fixedrank_algo, 'CG')...
                || strcmp(fixedrank_algo, 'SD'))
            warning('low_rank_dist_completion:problem_description', ...
                'The field "fixedrank_algo" is not one of the choices. We work with the default "TR".\n');
            
            fixedrank_algo = 'TR';
        end
    else
        warning('low_rank_dist_completion:problem_description', ...
            'The field "fixedrank_algo" is not defined. We work with the default "TR".\n');
        
        fixedrank_algo = 'TR';
    end
    checked_problem_description.fixedrank_algo = fixedrank_algo;
    
    
    
    % Check initial rank
    if ~isfield(problem_description, 'rank_initial')...
            || isempty(problem_description.rank_initial)...
            || ~(floor(problem_description.rank_initial) == problem_description.rank_initial)
        warning('low_rank_dist_completion:problem_description', ...
            'The field "rank_initial" is not properly defined. We work with the default "1".\n');
        
        rank_initial = 1;
    end
    checked_problem_description.rank_initial = rank_initial;
    
    
    
    % Check maximum rank
    if ~isfield(problem_description, 'rank_max')...
            || isempty(problem_description.rank_max)...
            || ~(floor(problem_description.rank_max) == problem_description.rank_max)...
            || problem_description.rank_max > problem_description.n
        warning('low_rank_dist_completion:problem_description', ...
            'The field "rank_max" is not properly defined. We work with the default "n".\n');
        
        rank_max = problem_description.n;
    end
    checked_problem_description.rank_max = rank_max;
    
    
    
    % Check testing dataset
    if ~isfield(problem_description,{'data_test'})...
            || ~all(isfield(problem_description.data_test,{'cols', 'rows', 'entries'}) == 1)...
            || isempty(problem_description.data_test.cols)...
            || isempty(problem_description.data_test.rows)...
            || isempty(problem_description.data_test.entries)
        
        warning('low_rank_dist_completion:problem_description', ...
            'The field "data_set" is not properly defined. We work with the default "[]".\n');
        
        data_test = [];
    end
    checked_problem_description.data_test = data_test;
    
    
    
    % Check parameters
    if isfield(problem_description, 'params')
        params = problem_description.params;
        
    else
        params = struct();
        
    end
    params = mergeOptions(localdefaults, params);
    checked_problem_description.params = params;
    
    
    
    
    
end




%%
function  show_plots(problem_description, infos)
    fixedrank_algo = problem_description.fixedrank_algo;
    rank_change_stats = infos.rank_change_stats;
    
    rank_change_stats_rank = [rank_change_stats.rank];
    rank_change_stats_iter = [rank_change_stats.iter];
    rank_change_stats_iter = cumsum(rank_change_stats_iter);
    
    if strcmp(fixedrank_algo, 'TR'), fixedrank_algo_name='Trust-region'; end
    if strcmp(fixedrank_algo, 'CG'), fixedrank_algo_name='Conjugate gradient'; end
    if strcmp(fixedrank_algo, 'SD'), fixedrank_algo_name='Steepest descent'; end
    
    
    
    
    
    % Plot: train error
    fs = 20;
    figure('name', 'Training on the known distances');
    
    line(1:length([infos.cost]),log10([infos.cost]),'Marker','O','LineStyle','-','Color','blue','LineWidth',1.5);
    ax1 = gca;
    
    set(ax1,'FontSize',fs);
    xlabel(ax1,'Number of iterations','FontSize',fs);
    ylabel(ax1,'Cost (log scale) on known distances','FontSize',fs);
    
    ax2 = axes('Position',get(ax1,'Position'),...
        'XAxisLocation','top',...
        'YAxisLocation','right',...
        'Color','none',...
        'XColor','k');
    
    set(ax2,'FontSize',fs);
    line(1:length([infos.cost]),log10([infos.cost]),'Marker','O','LineStyle','-','Color','blue','LineWidth',1.5,'Parent',ax2);
    set(ax2,'XTick',rank_change_stats_iter(1:end-1),...
        'XTickLabel',rank_change_stats_rank(1) + 1 : rank_change_stats_rank(end-1) + 1,...
        'YTick',[]);
    
    set(ax2,'XGrid','on');
    legend(fixedrank_algo_name);
    title('Rank');
    legend 'boxoff';
    
    
    % Plot: test error
    if isfield(infos, 'test_error')
        Yo = problem_description.Yo;
        
        fs = 20;
        figure('name','Test error on a set of distances different from the training set');
        
        line(1:length([infos.test_error]),log10([infos.test_error]),'Marker','O','LineStyle','-','Color','blue','LineWidth',1.5);
        ax1 = gca;
        
        set(ax1,'FontSize',fs);
        xlabel(ax1,'Number of iterations','FontSize',fs);
        ylabel(ax1,'Cost (log scale) on testing set','FontSize',fs);
        
        ax2 = axes('Position',get(ax1,'Position'),...
            'XAxisLocation','top',...
            'YAxisLocation','right',...
            'Color','none',...
            'XColor','k');
        
        set(ax2,'FontSize',fs);
        line(1:length([infos.test_error]),log10([infos.test_error]),'Marker','O','LineStyle','-','Color','blue','LineWidth',1.5,'Parent',ax2);
        set(ax2,'XTick',rank_change_stats_iter(1:end-1),...
            'XTickLabel',rank_change_stats_rank(1) + 1 : rank_change_stats_rank(end-1) + 1,...
            'YTick',[]);
        
        set(ax2,'XGrid','on');
        legend(fixedrank_algo_name);
        title('Rank');
        legend 'boxoff';
        
        
        
    end
    
    
    % Plot: visualize Helix curve with ranks
    if isfield(problem_description, 'helix_example')
        jj = ceil((length(rank_change_stats_rank) + 1)/2);
        
        
        figure('name','3D structure')
        fs = 20;
        ax1 = gca;
        set(ax1,'FontSize',fs);
        subplot(jj,2,1);
        plot3(Yo(:,1), Yo(:,2), Yo(:,3),'*','Color', 'b','LineWidth',1.0);
        title('Original 3D structure');
        for kk = 1 : length(rank_change_stats_rank)
            subplot(jj, 2, kk + 1);
            rank_change_stats_kk = rank_change_stats(kk);
            Ykk = rank_change_stats_kk.Y;
            if size(Ykk, 2) == 1,
                plot3(Ykk(:,1), zeros(size(Ykk, 1)), zeros(size(Ykk, 1)),'*','Color', 'r','LineWidth',1.0);
                legend(fixedrank_algo_name)
                title(['Recovery at rank ',num2str(size(Ykk, 2))]);
                
            elseif size(Ykk, 2) == 2
                plot3(Ykk(:,1), Ykk(:,2), zeros(size(Ykk, 1)),'*','Color', 'r','LineWidth',1.0);
                title(['Recovery at rank ',num2str(size(Ykk, 2))]);
                
            else  % We need to project onto the 3D dominant subspace.
                [U1, S1, V1] = svds(Ykk, 3);
                Yhat = U1*S1*V1';
                plot3(Yhat(:,1), Yhat(:,2), Yhat(:,3),'*','Color', 'r','LineWidth',1.0);
                title(['Recovery at rank ',num2str(size(Ykk, 2))]);
            end
            
        end
        ha = axes('Position',[0 0 1 1],'Xlim',[0 1],'Ylim',[0 1],'Box','off','Visible','off','Units','normalized', 'clipping' , 'off' );
        text(0.5, 1,'\bf Recovery of the Helix structure with rank','HorizontalAlignment','center','VerticalAlignment', 'top');
    end
    
    
    
    
end