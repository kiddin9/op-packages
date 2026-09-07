function omitEmptyReplacer(_: string, value: any) {
    if (Array.isArray(value) && value.length === 0) {
        return undefined;
    }
    if (value === null) {
        return undefined;
    }
    if (typeof value === 'number' && !Number.isFinite(value)) {
        return undefined;
    }
    if (typeof value === 'string' && !value.trim()) {
        return undefined;
    }
    return value;
}

const JsonUtils = {
    omitEmptyReplacer,
}

export { JsonUtils }
