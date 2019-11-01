function lc_InsertSepLineToNet(net,sepIndex)
% �˴���Ĺ��ܣ���һ����������ֲ�������ָ��ߣ��˷ָ��߽���ͬ��������ֿ�
% input
%   net:һ���������N*N,NΪ�ڵ����������Ϊ�Գƾ���
%   sepIndex:�ָ��ߵ�index��Ϊһ������������[3,9]��ʾ����ָ��߷ֱ�λ��3��9����
%% input
if nargin < 2
    %     sepIndex=2*[0,5,10,17,28,30,44,57];% Yeo17 net atals
    sepIndex=importdata('D:\WorkStation_2018\WorkStation_dynamicFC_V2\Data\Network_and_plot_para\sepIndex.mat');
end

if size(net,1)~=size(net,2)
    error('Not a symmetric matrix!\n');
end

%%
% figure
% figure;
imagesc(net)
% insert separate line
lc_line(sepIndex,length(net))
axis off
end

function lc_line(sepIndex,nNode)
% nNode: node����
for i=1:length(sepIndex)
    line([sepIndex(i)+0.5,sepIndex(i)+0.5],[-10,nNode*2],'color','k','LineWidth',0.8)
    line([0,nNode*2],[sepIndex(i)+0.5,sepIndex(i)+0.5],'color','k','LineWidth',0.8)
end
end