import { structuredPatch } from 'diff';

// 只限制预览，不改变草稿或上传内容。少量修改的大文件仍可显示完整差异。
export function fileDiff(original: string, content: string): { lines: string[]; truncated: boolean } {
    const patch = structuredPatch('original', 'draft', original, content, '', '',
        { context: 3, timeout: 100, maxEditLength: 2000 });
    if (!patch) return { lines: [], truncated: true };
    const lines: string[] = [];
    let truncated = false;
    for (const hunk of patch.hunks) {
        if (lines.length >= 500) return { lines, truncated: true };
        lines.push(`@@ -${hunk.oldLines ? hunk.oldStart : hunk.oldStart - 1},${hunk.oldLines} +${hunk.newLines ? hunk.newStart : hunk.newStart - 1},${hunk.newLines} @@`);
        for (const line of hunk.lines) {
            if (lines.length >= 500) return { lines, truncated: true };
            lines.push(line.length > 2000 ? line.slice(0, 2000) + '…' : line);
            if (line.length > 2000) truncated = true;
        }
    }
    return { lines, truncated };
}
