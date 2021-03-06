%% 
addpath('../experiments');
addpath('../formulation');
addpath('../misc');
exp = experiment('test', 'network.name', 'case_ieee30');
ac = exp.network.model;
ac.set_WPG_bus(22);
wind = exp.wind.model;
t = 1;


%% check equivalence of 

W_square = sdpvar(2*ac.N_b);
Obj = objective_PG(W_square);
C = [feasibleW(W_square, wind.P_wf(t)), W_square >= 0];

optimize(C, Obj);
Wopt = value(W_square);
Obj1 = value(Obj);
X=sqrt(diag(Wopt)).*sign(Wopt(:,1));
Xr = X(1:ac.N_b);
Xi = X(ac.N_b+1:2*ac.N_b);
Vbc = Xr + Xi * 1i;

[PG1, QG1] = extract_dispatch(Wopt, t);
% 
% W_complex = Vbc * Vbc';
%% 
yalmip('clear');
W = sdpvar(2*ac.N_b);
Obj = objective_PG(W);
C = [feasibleW(W, wind.P_wf(t)), PSD_bags(W, ac.bags)];
optimize(C, Obj);
Obj2 = value(Obj);
W_incomplete = value(W);
X=sqrt(diag(W_incomplete)).*sign(W_incomplete(:,1));
Xr = X(1:ac.N_b);
min(check(C))
%%
[W_completed, Vbc2] = completeW(W_incomplete);
[PG2, QG2] = extract_dispatch(W_completed, t);
% C = [feasibleW(W, wind.P_wf(t)), W >= 0];
assign(W, W_completed);
res = check(C);
min(res)

%% plot
initfig('Voltage profile', 1);
subplot(211)
hold on; grid on; box on;
plot(abs(Vbc), 'o', 'markersize', 10)
plot(abs(Vbc2), 'x', 'markersize', 10)
ylabel('Voltage magnitude');
set(gca, 'xtick', 1:31)
xlim([0.5 30.5])

set(gca, 'xticklabels', []);
stretchY(gca, 1);
title('Comparison of voltage profile');

subplot(212)
hold on; grid on; box on;
plot(angle(Vbc), 'o', 'markersize', 10)
plot(angle(Vbc2), 'x', 'markersize', 10)
xlabel('Bus number');
ylabel('Voltage angle');
set(gca, 'xtick', 1:31)
xlim([0.5 30.5])
stretchY(gca, 10);

legend('full', 'decomposed');

%% plot 2
initfig('Voltage profile', 2);
% %%
% 
% network_topology = zeros(ac.N_b);
% for l = 1:ac.N_l
%     network_topology(ac.from_to(l,1), ac.from_to(l,2)) = 1;
%     network_topology(ac.from_to(l,2), ac.from_to(l,1)) = 1;
% end
% network_topology = network_topology + eye(ac.N_b);
% clf
% hold on;
% spy(network_topology, '*r');
%     
% data_sparsity = zeros(ac.N_b);
% for k = 1:ac.N_b
%     data_sparsity = data_sparsity + abs(ac.Y_P(k)) + abs(ac.Y_Q(k));
% end
% 
% spy(data_sparsity, '+g');
% 
% %%
% 
% clf
% hold on;
% 
% network_topology = zeros(ac.N_b*2);
% for l = 1:ac.N_l
%     network_topology(ac.from_to(l,1), ac.from_to(l,2)) = 1;
%     network_topology(ac.from_to(l,1)+ac.N_b, ac.from_to(l,2)) = 1;
%     network_topology(ac.from_to(l,1), ac.from_to(l,2)+ac.N_b) = 1;
%     network_topology(ac.from_to(l,1)+ac.N_b, ac.from_to(l,2)+ac.N_b) = 1;
%     
%     network_topology(ac.from_to(l,2), ac.from_to(l,1)) = 1;   
%     network_topology(ac.from_to(l,2)+ac.N_b, ac.from_to(l,1)) = 1;   
%     network_topology(ac.from_to(l,2), ac.from_to(l,1)+ac.N_b) = 1;   
%     network_topology(ac.from_to(l,2)+ac.N_b, ac.from_to(l,1)+ac.N_b) = 1;   
% end
% network_topology = network_topology + eye(2*ac.N_b);
% clf
% hold on;
% spy(network_topology, '*r');
% 
% data_sparsity = zeros(2*ac.N_b);
% for k = 1:ac.N_b
%     data_sparsity = data_sparsity + abs(ac.Y_(k)) + abs(ac.Ybar_(k));
% end
% 
% for l = 1:ac.N_l
%     data_sparsity = data_sparsity + abs(ac.Y_lm(l)) + abs(ac.Ybar_lm(l));
% end
% 
% spy(data_sparsity, '+g');