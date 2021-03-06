function C = DC_cons_scen_single(x, dc, wind, j_des)
% C = AC_cons_scen(x, ac, wind, t_wind, j_des)
% returns an LMI with all the constraints, not aggregated
% if j_des < 0, returns only the psd constraint

    if nargin < 4
        j_des = 0;
    end
    
    C = [];
    
    % retrieve 1
    if j_des > 0
        [g, labels] = DC_g(x, dc, wind, j_des);
        C = [(g >= 0):labels{j_des}];
    
    % retrieve all
    else
        [g, labels] = DC_g(x, dc, wind);
        
        for j = 1:length(g)
            C = [C, (g(j) >= 0):labels{j}];
        end
    end
    
end