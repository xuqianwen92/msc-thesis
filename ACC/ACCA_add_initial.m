%% [xstar, its] = ACCA(x_sdp, deltas, objective_fcn, constraints_fcn, ...)
% Executes the Active Constraint Consensus Agreement algorithm to solve the
% optimization problem: 
%  min_x f(x)
%  s.t. constraints(x, delta_i) for i = 1, ..., N
%
% PARAMETERS
% ==========
% x_sdp         : optimization variable (sdpvar)
% f             : function handle for the objective function
% constraints   : a function that returns an LMI object 
% deltas        : a N x .. matrix with realizations of delta on the rows
% options       : key value pairs, optional, of following format:
%  - verbose    : flag to show progress, 1 = show (default), 0 = hide
%  - opt_settings : sdpsettings for optimization (default verbose=0)
%  - default_constriant : default (deterministic constraint)
%  - diameter   : diameter of connectivity graph (default 3)
%  - n_agents   : number of agents (default ceil(N/10))
%  - debug      : enter debugging inside function on error (default 0)
%  - x0         : initial value for x (if empty, zeros)
%  - max_its    : maximum no of iterations (default 100)
%  - residuals  : function handle to evaluate residuals h(x,delta) >= 0
%                 optional, when empty the check function of yalmip will be
%                 used
%  - use_selector : boolean to indicate that the constraint function
%                   accepts a third argument h(x, delta, j) >= 0 for
%                   selection. 
%  - connectivity : adjacency matrix of the connectivity graph
%  - stepsize   : stepsize function handle of the form @(k) ...,          
%                 default 1/(k+1)
%
% RETURNS
% =======
% xstar         : optimal value for x after convergence
% agents        : structure with iterations

function [xstar, agents] = ACCA_fcn2(x_sdp, deltas, f, cons_fcn, varargin)
    %% check validity of input and load options
    % check types of input
    assert(isa(x_sdp, 'sdpvar'), 'x_sdp should be sdpvar');
    assert(isa(f, 'function_handle'), 'f should be function handle');
    assert(isa(cons_fcn, 'function_handle'), ...
                                       'constraints should be a function');
  
    % store dimensions
    d = size(x_sdp);
    N= size(deltas, 1);
    Ncons = length(cons_fcn);
    
    % define default options
    options = struct('verbose', 0, ...
                     'opt_settings', sdpsettings('verbose', 0), ...
                     'x0', [], ...
                     'default_constraint', [], ...
                     'diameter', 3, ...
                     'debug', 0, ...
                     'n_agents', [],...
                     'max_its', 100, ...
                     'residuals', [],...
                     'use_selector', false,...
                     'connectivity', [],...
                     'stepsize', @(k)1/(k+1));
    def_fields = fieldnames(options);
    
    % load options from varargin
    nvarargin = length(varargin);
    assert(rem(nvarargin,2) == 0, 'Please provide key-value pairs');
    fields = varargin(1:2:end);
    values = varargin(2:2:end);
    
    % override options 
    for i = 1:length(fields)
        if find(strcmp(def_fields, fields{i}))
            options.(fields{i}) = values{i};
        else
            warning('Field "%s" is unknown. Typo?', fields{i});
        end
    end
    
    % set verbose flag
    if options.verbose == 1
        verbose = true;
    else
        verbose = false;
    end
    
    if options.debug == 1
        debug = true;
    else
        debug = false;
    end
    
    % set number of agents
    if isempty(options.n_agents)
        m = ceil(N/10);
    else
        assert(isnumeric(options.n_agents), 'Should be numeric');
        m = options.n_agents;
    end
    assert(N >= m, ...
            'Number of agents can not be larger than number of scenarios');
    
    
    if isempty(options.opt_settings.solver)
        warning('Calling optimizer with no solver specified!');
    end
    
    % add helper path
    if not(exist('zeros_like', 'file'))
        addpath('../misc/');
    end
    
    if isempty(options.x0)
        options.x0 = zeros_like(x_sdp);
    end
    
    % find connectivity graph
    if isempty(options.connectivity)
        if not(exist('digraph', 'file'))
            warning('Digraph function not found, using G from workspace');
            connectivity_graph = evalin('base', 'G');
        else 
            connectivity_graph = random_graph(m,options.diameter, 'rand');
        end
    else
        connectivity_graph = options.connectivity;
    end
    
    % use try block to enter debug mode inside function when encountering
    % error
    try      
        
        %% initialize agents
        agents = struct('initial_deltas', [], ...
                        'iterations', []);
                    
        
        
        % divide the initial deltas among the agents
        Nm = ceil(N/m);             % no of deltas per agent
        constraint_ids = [1:Ncons]';  % list with constraint identifiers
        for i = 1:m
            % store the deltas in the agent; the first entry of the row
            % will be the identifier of the constraint, the rest of the row
            % will be the actual data corresponding to that delta
            delta_slice = deltas(((i-1)*Nm)+1:min(i*Nm,N), :);
            identifiers = repmat(constraint_ids, size(delta_slice, 1), 1);
            agents(i).initial_deltas = [identifiers, ...
                                        kron(delta_slice, ones(Ncons, 1))];
                                    
        end
        
        [agents.iterations] = deal(struct(  'J', f(options.x0), ...
                        'active_deltas', [],...
                        'x', options.x0, ...
                        'time', nan));
            
        

                       
        %% start main iterations
        k = 1;
        ngc = ones(m, 1);
        loop_active = 1;
        
        while loop_active
            
            if verbose
                prg = progress(sprintf('Iteration %i',k), m);
            end

            % loop over agents
            for i = 1:m
                
                tic
                %% build C_i and z
                
                % build constraint set from C_i and A_i ...
                L = [agents(i).initial_deltas; ...
                     agents(i).iterations(k).active_deltas];
                 
                % build consensus variable z from average of own solution +
                % incoming constraints using constant weights a_*^i =
                % 1/(N+1)
                N_incoming = sum(connectivity_graph(:,i)) + 1;
                z = agents(i).iterations(k).x ./ N_incoming;
                
                % loop over neighbouring agents
                for j = find(connectivity_graph(:, i))';
                    % add A_j for all incoming agents j to constraint set
                    L = [L; agents(j).iterations(k).active_deltas];
                    
                    % sum up incoming xs devided by number of connections
                    z = z + (agents(j).iterations(k).x ./ N_incoming);
                end

                % filter out double deltas
                L = unique(L, 'rows');
                
                %% check feasibility of new set of constraints
                
                feasible_for_all = 1;
                for j = 1:size(L,1)
                    
                    if isempty(options.residuals) % use YALMIP check
                        cons_delta = cons_fcn(x_sdp, L(j, 2:end));
                        assign(x_sdp, agents(i).iterations(k).x);
                        residual = check(cons_delta(L(j, 1)));
                        
                    elseif options.use_selector % use h(x, delta, j) >= 0
                        residual = options.residuals(...
                                                agents(i).iterations(k).x, ...
                                                L(j, 2:end), L(j, 1));
                                            
                    else % use residual function h(x, delta) >= 0
                        % get all residuals
                        residuals = options.residuals(...
                                                agents(i).iterations(k).x, ...
                                                L(j, 2:end));
                        % filter out the residual of interest
                        residual = residuals(L(j,1));
                    end
                    
                    if residual < -1e-6;
                        feasible_for_all = 0;
                        break
                    end
                end
                
                %% update x
                
                % optimize if new z is not feasible
                if not(feasible_for_all) || k == 1
                    
                    N_cons_used = 0;
                    % build solver
                    C_i = [];
                    C_all = options.default_constraint; 
                    for j = 1:size(L,1)
                        
                        % check feasibility for z instead of x
                        if isempty(options.residuals) % use YALMIP check
                            cons_delta = cons_fcn(x_sdp, L(j, 2:end));
                            assign(x_sdp, z);
                            residual = check(cons_delta(L(j, 1)));

                        elseif options.use_selector % use h(x, delta, j) >= 0
                            residual = options.residuals(z, L(j, 2:end),...
                                                         L(j, 1));

                        else % use residual function h(x, delta) >= 0
                            % get all residuals
                            residuals = options.residuals(z, L(j, 2:end));
                            % filter out the residual of interest
                            residual = residuals(L(j,1));
                        end

                        % only use the constraints from infeasible deltas
                        if residual < -1e-6
                            C_i = [C_i; L(j, :)];
                             
                            % use previously defined cons_delta
                            if isempty(options.residuals)
                                C_all = [C_all, cons_delta(L(j,1))];
                                
                            % use cons_fcn with selector
                            elseif options.use_selector
                                C_all = [C_all, cons_fcn(x_sdp, ...
                                                             L(j, 2:end),...
                                                             L(j, 1))];
                            % use cons_fcn without selector
                            else
                                cons_delta = cons_fcn(x_sdp, L(j, 2:end));
                                C_all = [C_all, cons_delta(L(j, 1))];
                                
                            end
                                           
                            N_cons_used = N_cons_used + 1;
                        end
        
                    end
                    
%                     if N_cons_used == 0
%                         warning('Not using any outsider constraints...');
%                         % we should not get here....
%                     end
                    
                    % add own set of constraint to constraints
                    L = [L; agents(i).initial_deltas];
                    for j = 1:size(agents(i).initial_deltas, 1)
                        % use previously defined cons_delta
                        if isempty(options.residuals)
                            C_all = [C_all, ...
                                cons_delta(agents(i).initial_deltas(j,1))];

                        % use cons_fcn with selector
                        elseif options.use_selector
                            C_all = [C_all, cons_fcn(x_sdp, ...
                                     agents(i).initial_deltas(j, 2:end),...
                                     agents(i).initial_deltas(j, 1))];
                        % use cons_fcn without selector
                        else
                            cons_delta = cons_fcn(x_sdp, ...
                                       agents(i).initial_deltas(j, 2:end));
                            C_all = [C_all, ...
                               cons_delta(agents(i).initial_deltas(j, 1))];

                        end

                        N_cons_used = N_cons_used + 1;
                    end

                    % define objective and solve
                    alpha = options.stepsize(k);
                    Obj_consensus = f(x_sdp) + 1/(2*alpha) * ...
                                                   norm(x_sdp(:) - z(:))^2;
                    status = optimize(C_all, Obj_consensus, ...
                                                     options.opt_settings);
                    assert(not(status.problem), status.info);
                    next_x = value(x_sdp);
                    
                    agents(i).iterations(k+1).x = next_x;
                    agents(i).iterations(k+1).J = f(next_x);
                    
                    % store status
                    if debug
                        agents(i).iterations(k+1).info.optimized = 1;
                        agents(i).iterations(k+1).info.num_cons = N_cons_used;
                    end
                    
                else
                    agents(i).iterations(k+1).x = ...
                                                agents(i).iterations(k).x;
                    agents(i).iterations(k+1).J = ...
                                                agents(i).iterations(k).J;
                    
                    % store status
                    if debug
                        agents(i).iterations(k+1).info.optimized = 0;
                        agents(i).iterations(k+1).info.num_cons = size(L,1);
                    end
                end
                
                % store active constraints
                agents(i).iterations(k+1).active_deltas = [];
                for j = 1:size(L,1)
                    
                    % check feasibility of of the new solution
                    if isempty(options.residuals) % use YALMIP check
                        cons_delta = cons_fcn(x_sdp, L(j, 2:end));
                        assign(x_sdp, agents(i).iterations(k+1).x);
                        residual = check(cons_delta(L(j, 1)));
                        
                    elseif options.use_selector % use h(x, delta, j) >= 0
                        residual = options.residuals(...
                                                agents(i).iterations(k).x, ...
                                                L(j, 2:end), L(j, 1));
                                            
                    else % use residual function h(x, delta) >= 0
                        % get all residuals corresponding to the delta
                        residuals = options.residuals(...
                                                agents(i).iterations(k).x, ...
                                                L(j, 2:end));
                        % filter out the residual of interest
                        residual = residuals(L(j,1));
                    end

                    if residual < 1e-6 && residual > -1e-6;
                        agents(i).iterations(k+1).active_deltas = [
                            agents(i).iterations(k+1).active_deltas;
                            L(j, :)];
                    end
                end
                
                % check if J(t+1) is J(t)
                if all_close(agents(i).iterations(k).J, agents(i).iterations(k+1).J, 1e-6)
                    ngc(i) = ngc(i) + 1;
                else
                    ngc(i) = 1;
                end
                
                if verbose
                    prg.ping();
                end
                
                agents(i).iterations(k+1).time = toc;
            end

            % update iteration number     
            k = k + 1;
            
            if all(ngc >= 2*options.diameter+1)
                loop_active = 0;
            elseif k >= options.max_its
                warning(['Maximum iterations (%i) is reached, '...
                           'might not have convergence'], options.max_its);
                loop_active = 0;
            end
        end
        
        % check if everything went well
        for i = 1:m
            for j = i+1:m
                if not(all_close(agents(i).iterations(k).x, ...
                                 agents(j).iterations(k).x, 1e-3))
                    warning('Agents not close, xstar may not be optimal'); 
                end
            end
        end
        
        xstar = agents(1).iterations(k).x;
            

        %% return output
    catch e
        if debug
            fprintf('\n%s', e.getReport());
            keyboard;
        else
            rethrow(e);
        end
    end
end