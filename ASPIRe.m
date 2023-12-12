% unknown map version

% clc 
clear % clear global variables
close all

t_search_all = [];
loss_rate_all = [];
est_err_all = [];
time_search_all = [];
time_tracking_all = [];

for zz = 1:5
t_search = zeros(50,1);
traj_length = zeros(50,1);
t_loss = zeros(50,1);
estimation_error = zeros(50,1);
time_search = zeros(50,1);
time_tracking = zeros(50,1);
runtime = zeros(50,1);

for tt = 1:50 %1:50 %44 %47

% set up parameters
simSetup;

dbstop if error
%% %%%%%%%%%%%%%%% Simulation %%%%%%%%%%%%%%% 
% record the optimal solution of current time for warm starting ngPlanner
optz = [];
optu = [];

% save figures to video
if save_video
    vidObj = VideoWriter(sprintf('unknown_%s_%s_%d_%d_%s.avi',plan_mode,sensor_type,zz,tt,datetime('today')));
    vidObj.FrameRate = 3;
    open(vidObj);
end

list = repmat(Node_IMPFT,210,500);

error = zeros(200,1);

for ii = 1:sim_len
    %fprintf('[main loop] gameSim.m, line %d, iteration %d, Progress: %d\n',MFileLineNr(),ii,ii/sim_len)

    %% target moves
    %fld = fld.targetMove(tt,ii);
    %{
    if ~rbt.is_tracking
        pos_tmp = fld.target.pos(1:2) -1 + 1.8*[rand;rand];
        %flag = any([1;1] >= pos_tmp(1:2))||any([49;49] <= pos_tmp(1:2))||~fld.map.region(ceil(pos_tmp(1)),ceil(pos_tmp(2)));
        while(any([1;1] >= pos_tmp(1:2))||any([49;49] <= pos_tmp(1:2))||~fld.map.region(ceil(pos_tmp(1)),ceil(pos_tmp(2))))
            pos_tmp = fld.target.pos(1:2) + [rand;rand];
        end
    else 
        pos_tmp = fld.target.pos(1:2) + 0.2*(fld.target.pos(1:2)-rbt.state(1:2)) + [rand;rand];
        %flag = any([1;1] >= pos_tmp(1:2))||any([49;49] <= pos_tmp(1:2))||~fld.map.region(ceil(pos_tmp(1)),ceil(pos_tmp(2)));
        while(any([1;1] >= pos_tmp(1:2))||any([49;49] <= pos_tmp(1:2))||~fld.map.region(ceil(pos_tmp(1)),ceil(pos_tmp(2))))
            pos_tmp = fld.target.pos(1:2) + [rand;rand];
        end
    end
    %}

    %{
    pos_tmp = fld.target.pos(1:2) -3 + 6*[rand;rand];
    %flag = any([1;1] >= pos_tmp(1:2))||any([49;49] <= pos_tmp(1:2))||~fld.map.region(ceil(pos_tmp(1)),ceil(pos_tmp(2)));
    while(any([1;1] >= pos_tmp(1:2))||any([49;49] <= pos_tmp(1:2))||~fld.map.region(ceil(pos_tmp(1)),ceil(pos_tmp(2))))
        pos_tmp = fld.target.pos(1:2) + [rand;rand];
    end
    fld.target.pos(1:2) = pos_tmp;
    %}
    Q_tmp = [0.001 0;0 0.001];
    if ii <= 10
        move = mvnrnd([-0.5;0]',Q_tmp)';
    elseif ii <= 20
        move = mvnrnd([0;-0.5]',Q_tmp)';
    elseif ii <= 30
        move = mvnrnd([0.5;0]',Q_tmp)';
    elseif ii <= 67
        move = mvnrnd([0;-0.5]',Q_tmp)';
    elseif ii <= 79
        move = mvnrnd([-0.5;0]',Q_tmp)';
    elseif ii <= 119
        move = mvnrnd([0;-0.5]',Q_tmp)';
    elseif ii <= 150
        move = mvnrnd([-0.5;0]',Q_tmp)';
    elseif ii <= 170
        move = mvnrnd([0;0.5]',Q_tmp)';
    else
        move = mvnrnd([-0.4;0]',Q_tmp)';
    end

    move = 0;
    fld.target.pos(1:2) = fld.target.pos(1:2) + move;

    fld.target.traj = [fld.target.traj;fld.target.pos'];

    rbt.is_tracking = 0;
    if rbt.inFOV(rbt.state,fld.target.pos)&&fld.map.V(ceil(rbt.state(1)),ceil(rbt.state(2)),ceil(fld.target.pos(1)),ceil(fld.target.pos(2)))
        rbt.is_tracking = 1;
    end

    %% target position estimation
    rbt.y = rbt.sensorGen(fld);

    lidarnum = 30;
    ranges = zeros(lidarnum,1);
    angles = linspace(-pi/4,pi/4,lidarnum);
    maxrange = rbt.rmax;

    intsectionPts = rayIntersection(fld.map.occ_map,rbt.state(1:3)',angles,maxrange,0.8);

    for jj = 1:size(intsectionPts,1)
        if ~isnan(intsectionPts(jj,1))
            ranges(jj) = norm(intsectionPts(jj,:)-rbt.state(1:2)')+0.1+normrnd(0,rbt.R(1,1));
            while(ranges(jj)<=0)
                ranges(jj) = norm(intsectionPts(jj,:)-rbt.state(1:2)')+0.1+normrnd(0,rbt.R(1,1));
            end
            %ranges(jj) = 6;
        else
            ranges(jj) = maxrange+0.1;
        end
    end

    scan = lidarScan(ranges,angles);

    insertRay(rbt.map.occ_map,rbt.state(1:3)',scan,maxrange);

    rbt.map.region = occupancyMatrix(rbt.map.occ_map);

    region_tmp = rbt.map.region';
    region1 = zeros(50,50);

    for jj = 1:size(region_tmp,2)
        region1(:,jj) = region_tmp(:,size(region_tmp,2)-jj+1);
    end
    rbt.map.region = 1-region1;
    rbt.map.region_exp = rbt.map.region;

    %% particle filtering
    [rbt.particles,rbt.w] = rbt.PF(fld,sim,tt,ii,rbt.state,rbt.particles,rbt.w,rbt.y,1);
    rbt.est_pos = rbt.particles*rbt.w';

    error(ii) = norm(rbt.est_pos(1:2)-fld.target.pos(1:2));

    rbt.inFOV_hist = [rbt.inFOV_hist rbt.is_tracking];

    % hgrid
    particles = rbt.particles;
    w = rbt.w;
    Cidx = zeros(size(particles,2),2);
    flag = zeros(4,4);
    N = 0;
    grid_size = rbt.map.size/4;
    for mm = 1:size(particles,2)
        id1 = ceil(particles(1,mm)/grid_size);
        Cidx(mm,1) = id1;
        id2 = ceil(particles(2,mm)/grid_size);
        Cidx(mm,2) = id2;
        if flag(id1,id2) == 0
            N = N + 1;
            flag(id1,id2) = N;
        end
    end
    %N
    particles_tmp = particles;
    w_tmp = w;
    particles = zeros(3,N);
    w = zeros(1,N);
    for mm = 1:size(particles_tmp,2)
        w(flag(Cidx(mm,1),Cidx(mm,2))) = w(flag(Cidx(mm,1),Cidx(mm,2))) + w_tmp(mm);
    end
    for mm = 1:size(particles_tmp,2)
        particles(:,flag(Cidx(mm,1),Cidx(mm,2))) = particles(:,flag(Cidx(mm,1),Cidx(mm,2))) + particles_tmp(:,mm).*w_tmp(mm)./w(flag(Cidx(mm,1),Cidx(mm,2)));
    end

    Cidx = zeros(size(particles,2),2);
    flag = zeros(2,2);
    N = 0;
    grid_size = rbt.map.size/2;
    for mm = 1:size(particles,2)
        id1 = ceil(particles(1,mm)/grid_size);
        Cidx(mm,1) = id1;
        id2 = ceil(particles(2,mm)/grid_size);
        Cidx(mm,2) = id2;
        if flag(id1,id2) == 0
            N = N + 1;
            flag(id1,id2) = N;
        end
    end
    %N
    particles_tmp = particles;
    w_tmp = w;
    particles_tmp2 = zeros(3,N);
    w = zeros(1,N);
    for mm = 1:size(particles_tmp,2)
        w(flag(Cidx(mm,1),Cidx(mm,2))) = w(flag(Cidx(mm,1),Cidx(mm,2))) + w_tmp(mm);
    end
    ll = 1;
    for mm = 1:size(particles_tmp,2)
        if w(flag(Cidx(mm,1),Cidx(mm,2))) < 0.3
            particles_tmp2(:,flag(Cidx(mm,1),Cidx(mm,2))) = particles_tmp2(:,flag(Cidx(mm,1),Cidx(mm,2))) + particles_tmp(:,ll).*w_tmp(ll)./w(flag(Cidx(mm,1),Cidx(mm,2)));
            particles_tmp(:,ll) = [];
            w_tmp(ll) = [];
            ll = ll - 1;
        end
        ll = ll+1;
    end

    rbt.first_particles = [particles_tmp particles_tmp2];
    rbt.first_w = [w_tmp w];

    kk = 1;
    for jj = 1:size(rbt.first_particles,2)
        if norm(rbt.first_particles(:,kk)) == 0 || rbt.first_w(kk) < 0.10
            rbt.first_particles(:,kk) = [];
            rbt.first_w(kk) = [];
            kk = kk-1;
        end
        kk = kk+1;
    end

    %     for jj = size(rbt.particles,2)
    %         x = floor(rbt.particles(jj,1)/(rbt.map.size/2));
    %         y = floor(rbt.particles(jj,2)/(rbt.map.size/2));
    %         if x==1&&y==1
    %             rbt.hgrid(4,1) = rbt.hgrid(4,1)+rbt.w(jj);
    %         elseif x==2&&y==1
    %             rbt.hgrid(4,2) = rbt.hgrid(4,2)+rbt.w(jj);
    %         elseif x==1&&y==2
    %             rbt.hgrid(4,3) = rbt.hgrid(4,3)+rbt.w(jj);
    %         elseif x==2&&y==2
    %             rbt.hgrid(4,4) = rbt.hgrid(4,4)+rbt.w(jj);
    %         end
    %     end

%     kk = 1;
%     for jj = 1:size(rbt.first_particles,2)
%         %rbt.hgrid = [rbt.map.size/2;0;0 rbt.map.size/2;rbt.map.size/2;0 rbt.map.size/2;0;rbt.map.size/2 rbt.map.size/2;rbt.map.size/2;rbt.map.size/2];
%         if rbt.first_w(kk) < 0.05
%             rbt.first_particles(kk) = [];
%             kk = kk - 1;
%         elseif rbt.first_w(kk) > 0.3
%             
%             
%             rbt.first_particles(kk) = [];
%             kk = kk - 1;
%         end
%         kk = kk + 1;
%     end

    if ii > 1
        wrong = 0;
        for jj = 0:20
            if ~fld.map.region(ceil(rbt.traj(1,end-jj)),ceil(rbt.traj(2,end-jj)))
                wrong = 1;
                break
            end
        end
        if wrong
            disp('Collision.');
            %pause
            pause(1);
            break
        end
    end

    %% robot motion planning
    tic

    if strcmp(plan_mode,'NBV')
        % (TODO: changliu) legacy code. will clean up later.
        %         [optz,optu] = rbt.cvxPlanner_kf(fld,optz,optu);
        %         [optz,optu,s,snum,merit, model_merit, new_merit] = rbt.cvxPlanner_scp(fld,optz,optu,plan_mode);
    elseif strcmp(plan_mode,'sampling')
        %[optz,optu,s,snum,merit, model_merit, new_merit] = rbt.cvxPlanner_scp(fld,optz,optu,plan_mode);
    elseif strcmp(plan_mode,'ASPIRe')
        [rbt,optz] = rbt.Planner(fld,sim,plan_mode,ps,pt,tt,ii);
    end

    t = toc
    %rbt.traj = [rbt.traj,optz];

    list(ii,1:length(rbt.tree)) = rbt.tree;

    % draw plot
    sim.plot_rbt_map(rbt,fld,tt,ii);
    %pause(0.2);

    rbt.state = optz;

% save the plot as a video
    frame = getframe(gcf);
    if save_video
        writeVideo(vidObj,frame);
    end   

    clf

    % skip tracking
    %
    if rbt.is_tracking
        pause(1);
        clf
        break
    end
    %}

    if rbt.is_tracking
    time_tracking(tt) = time_tracking(tt) + t;
    else
    time_search(tt) = time_search(tt) + t;
    end
    runtime(tt) = runtime(tt) + t;    

    particles_all{zz,tt,ii} = rbt.particles;
    est_all{zz,tt,ii} = rbt.est_pos;
    obs_all{zz,tt,ii} = rbt.y;
end

%     if ii == 166
%     ax = gca;
%     exportgraphics(ax,strcat('sim_0828_multi',num2str(ii),'.png'));
%     %exportgraphics(ax,strcat('sim_0828_',num2str(ii),'.png'));
%     end

traj_rbt{zz,tt} = rbt.traj;
% 
if save_video
    close(vidObj);
end

inFOV_time = find(rbt.inFOV_hist==1);
if ~isempty(inFOV_time)
    t_search(tt) = inFOV_time(1);
    t_loss(tt) = 200 - t_search(tt) + 1 - length(inFOV_time);
    traj_length(tt) = 0;
%     for ii = 2:t_search_inter
%         traj_length(tt) = traj_length(tt) + norm(traj1(1:2,ii) - traj1(1:2,ii-1));
%     end
    estimation_error(tt) = mean(error(t_search(tt):end));
end
fprintf('ASPIRe: search time: %d, loss time/tracking time: %d/%d\n', t_search(tt), t_loss(tt), 200-t_search(tt));
time_search(tt) = time_search(tt)/(t_search(tt)-1);
time_tracking(tt) = time_tracking(tt)/(201-t_search(tt));
runtime(tt) = runtime(tt)/200;
%}
end
t_search_all = [t_search_all t_search];
loss_rate_all = [loss_rate_all t_loss./(200-t_search)];
est_err_all = [est_err_all estimation_error];
time_search_all = [time_search_all time_search];
time_tracking_all = [time_tracking_all time_tracking];
end

%% save simulation result

save(sprintf("ASPIRe_%s_%s",prior_case,date),"est_err_all","loss_rate_all","t_search_all","particles_all","est_all","obs_all","traj_rbt");
% run resultAnalysis.m to analyze the simulation results
