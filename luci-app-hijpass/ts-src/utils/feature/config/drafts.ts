import type { Editor } from '../../backend';

export interface FileDraft {
    id: string[];
    editor: Editor;
    section: string;
    field: string;
    original: string;
    content: string;
    revision: string;
}

export const normalizeFile = (content: string) => (content || '').trim().replace(/\r\n/g, '\n');

// 一份文件一条记录，内容与关联信息在同一个 IndexedDB 事务中写入。
export class DraftStore {
    private database: Promise<IDBDatabase>;
    constructor(private session: string) {}
    private open() {
        return this.database ||= new Promise((resolve, reject) => {
            const request = indexedDB.open('hijpass-file-drafts', 1);
            request.onupgradeneeded = () => request.result.createObjectStore('files', { keyPath: 'id' });
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
    }
    key(editor: Editor) { return [this.session, editor.resource, editor.section || '']; }
    async transaction<T>(mode: IDBTransactionMode, operation: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
        const database = await this.open();
        return new Promise((resolve, reject) => {
            const transaction = database.transaction('files', mode);
            const request = operation(transaction.objectStore('files'));
            transaction.oncomplete = () => resolve(request.result);
            transaction.onabort = () => reject(transaction.error || new Error('File draft transaction failed'));
            transaction.onerror = () => reject(transaction.error);
        });
    }
    get(editor: Editor): Promise<FileDraft | undefined> {
        return this.transaction('readonly', store => store.get(this.key(editor)));
    }
    async list(): Promise<FileDraft[]> {
        return this.transaction('readonly', store => store.getAll(IDBKeyRange.bound([this.session], [this.session, []])));
    }
    async put(draft: FileDraft) { await this.transaction('readwrite', store => store.put(draft)); }
    // 只删除此次应用的版本，保留其他标签页在应用期间保存的新草稿。
    async remove(draft: FileDraft) {
        await this.transaction('readwrite', store => {
            const request = store.get(draft.id);
            request.onsuccess = () => {
                if (request.result?.revision === draft.revision) store.delete(draft.id);
            };
            return request;
        });
    }
    async complete(draft: FileDraft) {
        await this.transaction('readwrite', store => {
            const request = store.get(draft.id);
            request.onsuccess = () => {
                const current = request.result as FileDraft | undefined;
                if (current?.revision === draft.revision) store.delete(draft.id);
                else if (current && current.original === draft.original && current.editor.name === draft.editor.name)
                    store.put({ ...current, original: draft.content });
            };
            return request;
        });
    }
    async sessions(): Promise<string[]> {
        const keys = await this.transaction('readonly', store => store.getAllKeys());
        return [...new Set(keys.map(key => (key as string[])[0]))];
    }
    async clear(session = this.session) {
        await this.transaction('readwrite', store => {
            const request = store.openKeyCursor();
            request.onsuccess = () => {
                const cursor = request.result;
                if (!cursor) return;
                if ((cursor.key as string[])[0] === session) store.delete(cursor.key);
                cursor.continue();
            };
            return request;
        });
    }
}
