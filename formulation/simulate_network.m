function [flag, info] = simulate_network(ac, wind, Wf, dus, dds, t)
% [flag, info] = simulate_network(ac, wind, Wf, dus, dds, t)
% simulates the behaviour of a network and checks constraints
%
% ARGUMENTS
% =========
% ac    : instance of AC model
% wind  : instance of wind model with scenarios to test
% Wf    : squared bus voltages for forecasted scenario
% dus   : ACG upspinning distribution vector
% dds   : ACG downspinning distribution vector
% t     : time 
% 
% RETURNS
% =======
% flag  : integer to indicate problems (0 = no problems, 1 = problems)
% info  : string with information about where violation occured

    % check types of input
    check_class({ac, wind, Wf, dus, dds}, {'AC_model', 'wind_model', ...
                                            'double', 'double', 'double'})
    
    % check deterministic constraints
    j =  0;
    g = nan(ac.N_b * 6,1);
    tol = 1e-6;
    for k = 1:ac.N_b
        
        % P_inj upper (1) 
        j = j + 1;  
        g(j) = ... P_G
               trace(ac.Y_k(k)*Wf) + ac.P_D(t, k) - ac.C_w(k)*wind.P_wf(t) ...
               ... <= P_Gmax
               - ac.P_max(k);

        % P_inj lower (1)
        j = j + 1;  
        g(j) = ... P_G
               -(trace(ac.Y_k(k)*Wf) + ac.P_D(t, k) - ac.C_w(k)*wind.P_wf(t)) ...
               ... >= P_Gmin
               + ac.P_min(k);
        % Q_inj upper (2) 
        j = j + 1;  
        g(j) = ... Q_G
               trace(ac.Ybar_k(k)*Wf) + ac.Q_D(t, k) ...
               ... <= Q_Gmax
               - ac.Q_max(k);

        % Q_inj lower (2) 
        j = j + 1;  
        g(j) = ... Q_G
               -(trace(ac.Ybar_k(k)*Wf) + ac.Q_D(t, k)) ...
               ... >= Q_Gmin
               + ac.Q_min(k);
           
        % V_bus upper (3)
        j = j + 1;  
        g(j) = ... V_bus
               trace(ac.M_k(k)*Wf) ...
               ... <= (V_max)^2
               - (ac.V_max(k))^2;   

        % V_bus lower (3)
        j = j + 1; 
        g(j) = ... V_bus
               -(trace(ac.M_k(k)*Wf)) ...
               ... >= (V_min)^2
               + (ac.V_min(k))^2;

    end
    if any(g > tol) 
        flag = 1;
        info = 'Not satisfying deterministic constraints';
        return
    end
    
    % check for every scenario if a feasible solution is possible
    Ws = sdpvar(2*ac.N_b);
    Pm_pos = sdpvar(ac.N_w, 1, 'full'); % = max(0, P_m)
    Pm_neg = sdpvar(ac.N_w, 1, 'full'); % = max(0, -P_m)
    
    % refbus angle constraints
    refbus_index = ac.refbus + ac.N_b;
    C = [Ws(refbus_index, refbus_index) == 0];
            
    % psd constraints
    C = [C; Ws >= 0];
    
    for k = 1:ac.N_b
        % real power injection limits
        C = [C; ac.P_min(k) - ac.P_D(t, k) + ac.C_w(k)*(wind.P_wf(t)+Pm_pos+Pm_neg) <= ...
                trace(Ws * ac.Y_k(k)) <= ...
                ac.P_max(k) - ac.P_D(t, k) + ac.C_w(k)*(wind.P_wf(t)+Pm_pos+Pm_neg)];

        % reactive power injection limits
        C = [C; ac.Q_min(k) - ac.Q_D(t, k) <= ...
                trace(Ws * ac.Ybar_k(k)) <= ...
                ac.Q_max(k) - ac.Q_D(t, k)];
        
        % voltage magnitude limits
        C = [C; (ac.V_min(k))^2 <= ...
                trace(Ws * ac.M_k(k)) <= ...
                (ac.V_max(k))^2];
    end
    
    for j = 1:ac.N_G
        
        % bus index
        k = ac.Gens(j);
        
        % relate W_s and W_f through d_ds and d_us
        C = [C; trace((Ws - Wf) * ac.Y_k(k)) ...
                - ac.C_w(k)*(Pm_pos+Pm_neg) == ...
                - dus(j) * Pm_neg ...
                - dds(j) * Pm_pos];        
    end
    
    % define optimizer
    ops = sdpsettings('solver', 'mosek');
    check_feasibility = optimizer(C, [], ops, {Pm_pos, Pm_neg}, Ws);
    
    
    for i = 1:size(wind.P_m, 2)
        [Ws_opt, problem, msg] = check_feasibility(max(0, wind.P_m(t, i)), ...
                               min(0, wind.P_m(t, i)));
        if problem && strcmp(msg{:}, 'Infeasible problem ')
            flag = 1;
            info = sprintf('Not feasible for scenario %i\n%s', i, msg{:});
            return
        elseif problem
            warning(['Problem optimizing: ' msg{:}]);
        end
        
        if not(svd_rank(Ws_opt, 1e2) == 1)
            flag = 1;
            info = sprintf('Ws for scenario %i not rank 1', i);
            return
        end
    end
    
    flag = 0;
    info = 'Checked, no problem';
end