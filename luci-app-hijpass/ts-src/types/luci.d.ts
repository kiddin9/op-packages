// luci.d.ts

declare namespace LuCI {
    interface View {
        extend?(view: View): View;

        load?(): any | Promise<any>;

        render?(load_results?: any | null): Node | Promise.<Node>;

        handleSave?(ev?: Event): any | Promise<any>;

        handleSaveApply?(ev?: Event, mode?: string | number): any | Promise<any>;

        handleReset?(ev?: Event): any | Promise<any>;

        addFooter?(): DocumentFragment

        prototype?: View;
    }

    interface L {
        Poll: LuCI.poll.Poll
        dom: LuCI.dom.DOM

        resolveDefault(value: any, defvalue?: any): Promise<any>;

        bind(fn: function, self, ...args?): function

        url(...parts: string[]): string
    }

    declare namespace form {
        interface Form {
            Map: new (config: string, title: string, description?: string) => LuCI.form.Map;
            TypedSection: LuCI.form.TypedSection;
            Value: LuCI.form.Value;
            Flag: LuCI.form.FlagValue;
            ListValue: LuCI.form.ListValue;
            Button: LuCI.form.ButtonValue;
            DynamicList: LuCI.form.DynamicList;
            SectionValue: LuCI.form.SectionValue;
            TextValue: LuCI.form.TextValue;
            GridSection: LuCI.form.GridSection;
            MultiValue: LuCI.form.MultiValue;
            AbstractElement: LuCI.form.AbstractElement;
            DummyValue: LuCI.form.DummyValue;
        }

        interface AbstractElement {
            append(obj): void

            parse(): Promise<void>

            render(): Node | Promise.<Node>;

            stripTags(s): string

            titleFn(property, fmt_args): (string | null)
        }

        interface AbstractValue extends LuCI.form.AbstractElement {
            datatype: string
            default: any
            editable: boolean
            modalonly: boolean
            onchange: function
            optional: boolean
            readonly: boolean
            retain: boolean
            rmempty: boolean
            uciconfig: string
            ucioption: string
            ucisection: string
            validate: function
            width: number | string
            section: LuCI.form.AbstractSection

            cbid(section_id: string): string

            cfgvalue(section_id: string): any

            depends(field: (string | Object.<string, (string | RegExp)>), value?: (string | RegExp)): void

            formvalue(section_id: string): any

            getUIElement(section_id: string): (LuCI.ui.AbstractElement | null)

            getValidationError(section_id: string): string

            isActive(section_id: string): boolean

            isValid(section_id: string): boolean

            load(section_id: string): (* | Promise<*>)

            parse(section_id: string): (Promise<void>)

            remove(section_id: string): void

            textvalue(section_id: string): string | Node

            write(section_id: string, formvalue: string | Array<string>): void

            renderWidget(section_id: string, option_index: number, cfgvalue: string): Node;

        }

        interface AbstractSection extends LuCI.form.AbstractElement {
            map: LuCI.form.Map
            parentoption: AbstractValue
            selected_tab?: string

            prototype?: AbstractSection;

            append(obj): Array.<string>

            cfgvalue(section_id: string, option: string): any

            filter(section_id: string): boolean

            formvalue(section_id: string, option?: string): any

            getOption(option: string): null | LuCI.form.AbstractValue | Object.<string, LuCI.form.AbstractValue>

            getUIElement(section_id, option): null | LuCI.ui.AbstractElement | Object.<string, (null | LuCI.ui.AbstractElement)>

            load(): (Promise.<void>)

            option<T extends LuCI.form.AbstractValue>(optionclass: T, ...classargs: any): T

            parse(): Promise.<void>

            tab(name: string, title?: string, description?: string)

            // 重载签名 1：有 subsection 参数，返回 T
            taboption<T extends LuCI.form.AbstractSection>(
                tabName: string,
                optionclass: LuCI.form.SectionValue,
                option: string,
                subsection: T,
                ...classargs: any[]
            ): LuCI.form.SectionValue<T>;

            // 重载签名 2：没有 subsection，只传一个 optionclass，返回 T
            taboption<T extends LuCI.form.AbstractValue>(
                tabName: string,
                optionclass: T,
                ...classargs: any[]
            ): T;
        }

        interface Map extends LuCI.form.AbstractElement {
            data: any;

            lookupOption(name: string, section_id?: string, config_name?: string): [LuCI.form.AbstractValue, string] | null;

            section<T extends LuCI.form.AbstractSection>(sectionclass: T, ...classargs: any): T
        }

        interface TypedSection extends LuCI.form.AbstractSection {

            anonymous: boolean;
            addremove: boolean;
            sortable: boolean;
            nodescriptions: boolean;
            rowcolors: boolean;

            sectiontitle(sectionId: string): string;

            handleAdd?(ev: Event, name?: string): any;

            handleRemove?(sectionId: string, ev: Event): any;
        }

        interface MultiValue extends LuCI.form.DynamicList {
        }

        interface FlagValue extends LuCI.form.Value {
        }

        interface ListValue extends LuCI.form.Value {
            widget: string;
        }

        interface ButtonValue extends LuCI.form.Value {
            inputtitle: string;
            inputstyle: string;
            onclick: function;
        }

        interface DynamicList extends LuCI.form.Value {
        }

        interface SectionValue<T extends LuCI.form.AbstractSection> extends LuCI.form.Value {
            readonly subsection: T;
        }

        interface TextValue extends LuCI.form.Value {
        }

        interface Value extends LuCI.form.AbstractValue {
            forcewrite: boolean;
            prototype: Value
            monospace: boolean;
            rows: number;
            placeholder: string
            password: boolean;

            value(key: string, display?: string): void;
        }

        interface GridSection extends LuCI.form.TableSection {
            prototype?: GridSection;
            modaltitle: string | function;
            cloneable: boolean;
        }

        interface TableSection extends LuCI.form.TypedSection {
            rowcolors: boolean
        }

        interface DummyValue extends LuCI.form.Value {
        }

    }

    declare namespace ui {
        interface UI {
            changes: {
                apply(checked?: boolean): void;
            };

            showModal(modal: any, e: any): void;

            hideModal(): void;

            addTimeLimitedNotification(title?: string, children: any, timeout?: number, classes?: string): Node
        }

        interface AbstractElement {
            getValidationError(): string

            getValue(): string | Array<string> | null

            isChanged(): boolean

            isValid(): boolean

            registerEvents(targetNode: Node, synevent: string, events: Array<String>)

            render(): Node

            setChangeEvents(targetNode: Node, events: string)

            setPlaceholder(value: string | Array<string> | null)

            setUpdateEvents(targetNode: Node, events: string)

            setValue(value: string | Array<string> | null)

            triggerValidation()
        }
    }

    declare namespace uci {
        interface UCI {
            state: object;

            load(config: string): Promise<void>;

            add(config: string, type: string, name?: string): string;

            sections(config: string, type: string, callback: (section: any) => void): any[];

            sections(config: string, type: string): any[];

            get(config: string, sectionId: string, option?: string): any;

            get_first(config: string, type: string, option?: string): any;

            set(config: string, sectionId: string, option: string, value: any): void;

            unset(conf: string, sid: string, opt: string): void

            remove(config: string, sectionId: string): void;

            clone(config: string, type: string, sectionId: string, anonymous?: boolean, name?: string): void;

            set_first(config: string, sectionId: string, option: string, value: any): void;

            changes(): Promise.<Object.<string, Array.<string>>>

            save(): Promise<string[]>;
        }
    }

    declare namespace fs {
        interface FS {
            exec(command: string, args?: string[]): Promise<{ code: number; stdout: string; stderr: string; }>;

            write(path: string, content: string): Promise<void>;

            trimmed(path: string): Promise<string>;

            read(logFile: any): any;

            exec_direct(command: string, params?: string[], type?: "blob" | "text" | "json", latin1?: boolean): Promise<any>;
        }
    }

    declare namespace rpc {
        interface RPC {
            declare(spec: {
                object: string;
                method: string;
                params: string[];
                expect: any;
            }): (...args: any[]) => Promise<any>;
        }
    }

    declare namespace poll {
        interface Poll {
            add(fn: function, interval?: number): boolean;

            remove(fn: function): boolean;
        }
    }

    declare namespace baseclass {
        interface BaseClass {
            extend(obj: any): any;
        }
    }

    declare namespace network {
        interface Network {
            getNetworks(): Promise.<Array.<LuCI.network.Protocol>>

            getDevices(): Promise.<Array.<LuCI.network.Device>>

            getHostHints(): Promise.<LuCI.network.Hosts>
        }
    }
}

// 运行时存在的全局（由 luci 注入）
// declare const view: LuCI.View;
declare const L: LuCI.L;

// 全局函数
declare function _(text: string): string;

declare function E(tag: string, attrs?: Record<string, any>, ...children: any[]): Node;

// 声明String.format方法
declare interface String {
    format(template: string, ...args: any[]): string;
}

// 模块名 = require 名（view → 'require view'）

declare module 'view' {
    const v: LuCI.View;
    export default v;
}

declare module 'form' {
    const f: LuCI.form.Form;
    export default f;
}

declare module 'uci' {
    const uci: LuCI.uci.UCI
    export default uci
}

declare module 'fs' {
    const f: LuCI.fs.FS;
    export default f;
}

declare module 'rpc' {
    const r: LuCI.rpc.RPC;
    export default r;
}

declare module 'poll' {
    const p: LuCI.poll.Poll;
    export default p;
}

declare module 'baseclass' {
    const b: LuCI.baseclass.BaseClass;
    export default b;
}

declare module 'ui' {
    const u: LuCI.ui.UI;
    export default u;
}

declare module 'network' {
    const u: LuCI.network.Network;
    export default u;
}
