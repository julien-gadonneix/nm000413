% 批量处理 interictal state 结构的 EEG .mat 文件进行 HFO 检测，并以 Excel 形式保存每个文件的通道检测结果
clear; clc; close all;

% 设置根目录（仅处理 interictal state 子目录）
root_dir = "所用数据";

% 遍历所有 interictal state 文件夹下的 .mat 文件
file_list = dir(fullfile(root_dir, '**', 'interictal state', '*.mat'));
fprintf('共发现 %d 个 interictal state .mat 文件\n\n', numel(file_list));

results = [];

for i = 1:length(file_list)
    file_info = file_list(i);
    mat_path = fullfile(file_info.folder, file_info.name);
    fprintf('[%d/%d] 正在处理: %s\n', i, length(file_list), mat_path);

    try
        % 加载 .mat 文件
        S = load(mat_path);

        % === 提取 EEG 数据和采样信息 ===
        eeg = S.data;      % [time × channels]，interictal结构
        fs = S.sfreq;      % 采样率

        % 通道名称处理
        if isfield(S, 'ch_names')
            raw_labels = S.ch_names;
        elseif isfield(S, 'channel_names')
            raw_labels = S.channel_names;
        else
            raw_labels = {};
        end

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

        % 调用 HFO 检测器
        [RippleRate, FastRippleRate, Ripples, FastRipples] = HFODetector(eeg, fs);

        % 汇总结果
        total_ripple = sum(RippleRate);
        total_fast_ripple = sum(FastRippleRate);

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
        if isempty(channel_labels) || length(channel_labels) ~= channel_count
            channel_labels = strcat("Ch", string(1:channel_count));
        end

        T_channel = table((1:channel_count)', channel_labels(:), RippleRate(:), FastRippleRate(:), ...
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

% 输出为 CSV 汇总文件
T = struct2table(results);
writetable(T, fullfile(root_dir, 'HFO_detection_summary_interictal.csv'));

fprintf('\n✅ interictal state 文件处理完成，结果保存至 HFO_detection_summary_interictal.csv\n');
