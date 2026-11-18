import { CLIENT_DIR, SERVER_DIR, nodeFilename } from 'hijpass.config.paths';
import { run } from 'hijpass.command.runtime';

// 清理计划只包含固定目录和当前需保留的文件；实际删除由相邻 Shell 完成。
run(ARGV, args => {
    let kind = args[0], id = args[1], name = args[2];
    if (kind != 'proxy' && kind != 'server') {
        die('unknown node kind');
    }
    let file = nodeFilename({ '.name': id }, name);
    let directory = kind == 'proxy' ? CLIENT_DIR : SERVER_DIR;
    return { directory, keep: name ? `${directory}/${file}.json` : '' };
});
