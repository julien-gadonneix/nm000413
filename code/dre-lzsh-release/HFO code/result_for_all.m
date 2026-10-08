% 处理混合结构 EEG .mat 文件，逐通道输出 HFO 率到 Excel 文件
clear; clc; close all;

% 设置根目录
root_dir = "所用数据";

% 查找所有 .mat 文件
file_list = dir(fullfile(root_dir, '**', '*.mat'));
fprintf('共发现 %d 个 .mat 文件\n\n', numel(file_list));

results = [];

for i = 1:length(file_list)
    file_info = file_list(i);
    mat_path = fullfile(file_info.folder, file_info.name);
    fprintf('[%d/%d] 正在处理: %s\n', i, length(file_list), mat_path);

    try
        % 加载 .mat 文件
        S = load(mat_path);

        % === 自动判断结构 ===
        if isfield(S, 'eeg_data') && isfield(S, 'info')
            eeg = S.eeg_data';        % [time × channels]
            fs = S.info.sfreq;
            raw_labels = S.info.ch_names;

        elseif isfield(S, 'data') && isfield(S, 'sfreq')
            eeg = S.data;             % [time × channels]
            fs = S.sfreq;
            raw_labels = S.ch_names;

        else
            error('未知的 .mat 文件结构');
        end

        % 通道标签处理
        if exist('raw_labels', 'var')
            if iscell(raw_labels)
                channel_labels = raw_labels;
            elseif isstring(raw_labels)
                channel_labels = cellstr(raw_labels);
            elseif ischar(raw_labels)
                channel_labels = cellstr(raw_labels);
            elseif isnumeric(raw_labels)
                channel_labels = cellstr(string(raw_labels));
            else
                channel_labels = {};
            end
        else
            channel_labels = {};
        end

        % 检测 HFO
        [RippleRate, FastRippleRate, Ripples, FastRipples] = HFODetector(eeg, fs);

        % 汇总总率
        total_ripple = sum(RippleRate);
        total_fast_ripple = sum(FastRippleRate);

        % 保存整体结果
        results(end+1).File = mat_path;
        results(end).RippleRate_per_min = total_ripple;
        results(end).FastRippleRate_per_min = total_fast_ripple;
        results(end).Num_Ripples = size(Ripples, 1);
        results(end).Num_FastRipples = size(FastRipples, 1);
        results(end).Channels = size(eeg, 2);

        fprintf(' --> Ripple总率: %.2f 次/分钟 | FastRipple总率: %.2f 次/分钟\n', ...
            total_ripple, total_fast_ripple);

        % === 写入每通道数据到 Excel ===
        channel_count = length(RippleRate);
        if isempty(channel_labels)
            channel_labels = strcat("Ch", string(1:channel_count));
        end

        T_channel = table( ...
            (1:channel_count)', channel_labels(:), RippleRate(:), FastRippleRate(:), ...
            'VariableNames', {'ChannelIndex', 'ChannelLabel', 'RippleRate_per_min', 'FastRippleRate_per_min'});

        % 输出 Excel 路径
        [~, base_name, ~] = fileparts(mat_path);
        excel_path = fullfile(file_info.folder, base_name + "_HFO_rates.xlsx");

        writetable(T_channel, excel_path);
        fprintf('    ⬇ 每通道数据保存至: %s\n', excel_path);

    catch ME
        fprintf(' !!! 错误: %s\n', ME.message);
        results(end+1).File = mat_path;
        results(end).Error = ME.message;
    end
end

% 汇总写出总表
T_summary = struct2table(results);
writetable(T_summary, fullfile(root_dir, 'HFO_detection_summary_all.csv'));

fprintf('\n✅ 所有文件处理完成\n    - 每个文件通道结果已保存为 Excel\n    - 汇总结果保存为 HFO_detection_summary_all.csv\n');
