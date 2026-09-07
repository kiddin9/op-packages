require("luci.ip")

local params = {"iptype", "ipmatch", "domainmatch"}

local function ipType(ip)
    local result = nil

    result = luci.ip.checkip4(ip)
    if result then
        print(4)
        return 0
    end

    result = luci.ip.checkip6(ip)
    if result then
        print(6)
        return 0
    end

    return 1
end

local function domainMatch(host, rule_domain)
    if not host or not rule_domain then return false end

    -- 全小写，避免大小写问题
    host = host:lower()
    rule_domain = rule_domain:lower()

    if host == rule_domain then return true end

    -- 检查是否以 ".rule_domain" 结尾
    local suffix = "." .. rule_domain
    return host:sub(-#suffix) == suffix
end

local function ipMatch(ip, cidr)
    local range = luci.ip.new(cidr)
    return range:contains(ip)
end

local function checkParams(val)
    for _, v in ipairs(params) do if v == val then return true end end
    return false
end

local function readFile(filePath)
    local f, err = io.open(filePath, "r")
    if not f then
        io.stderr:write("cannot open cidr_file: " .. tostring(err) .. "\n")
        os.exit(2)
    end
    return f:lines()
end

local function ipMatchInFile(ip, filePath)
    for line in readFile(filePath) do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            if ipMatch(ip, trimmed) then return true end
        end
    end
    return false
end

local function domainMatchInFile(domain, filePath)
    for line in readFile(filePath) do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            if domainMatch(domain, trimmed) then return true end
        end
    end
    return false
end

if not checkParams(arg[1]) then
    print("Invalid parameter")
    os.exit(1)
end

if arg[1] == "iptype" then os.exit(ipType(arg[2])) end

if arg[1] == "ipmatch" then
    local ok, result_or_err
    if arg[3] == "-f" then
        ok, result_or_err = pcall(ipMatchInFile, arg[2], arg[4])
    else
        ok, result_or_err = pcall(ipMatch, arg[2], arg[3])
    end
    if ok and result_or_err then
        print("matched")
        os.exit(0)
    else
        print("not matched")
        os.exit(1)
    end
end

if arg[1] == "domainmatch" then
    local ok, result_or_err = pcall(domainMatchInFile, arg[2], arg[3])

    if ok and result_or_err then
        print("matched")
        os.exit(0)
    else
        print("not matched")
        os.exit(1)
    end
end
