local pairs, print, error, tostring, type
    = pairs, print, error, tostring, type

local s, t, u = require"string", require"table", require"util"



local _ENV = u.noglobals() ----------------------------------------------------



local s_byte, s_sub, t_concat, t_insert, t_remove, t_unpack
    = s.byte, s.sub, t.concat, t.insert, t.remove, u.unpack

local   expose,   load,   map,   map_all, t_pack
    = u.expose, u.load, u.map, u.map_all, u.pack



return function(Builder, LL)
local evaluate, LL_ispattern =  LL.evaluate, LL.ispattern
local charset = Builder.charset



local compilers = {}


local
function compile(pt, ccache)
    -- print("Compile", pt.ptype)
    if not LL_ispattern(pt) then
        --[[DBG]]expose(pt)
        error("pattern expected")
    end
    local typ = pt.ptype
    if typ == "grammar" then
        ccache = {}
    elseif typ == "ref" or typ == "choice" or typ == "sequence" then
        if not ccache[pt] then
            ccache[pt] = compilers[typ](pt, ccache)
        end
        return ccache[pt]
    end
    if not pt.compiled then
         -- dprint("Not compiled:")
        -- LL.pprint(pt)
        pt.compiled = compilers[pt.ptype](pt, ccache)
    end

    return pt.compiled
end
LL.compile = compile

------------------------------------------------------------------------------
----------------------------------  ,--. ,--. ,--. |_  ,  , ,--. ,--. ,--.  --
--- Captures                        |    .--| |__' |   |  | |    |--' '--,
--                                  `--' `--' |    `-- `--' '    `--' `--'


-- These are all alike:


for k, v in pairs{
    ["C"] = "C",
    ["Cf"] = "Cf",
    ["Cg"] = "Cg",
    ["Cs"] = "Cs",
    ["Ct"] = "Ct",
    ["/string"] = "/string",
    ["/table"] = "/table",
    ["/number"] = "/number",
    ["/function"] = "/function",
} do
    compilers[k] = load(([[
    local compile = ...
    return function (pt, ccache)
        local matcher, aux = compile(pt.pattern, ccache), pt.aux
        return function (subject, index, cap_acc, cap_i, state)
             -- dprint("XXXX    ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            local new_acc, nindex, success = {
                type = "XXXX",
                start = index,
                aux = aux,
                parent = cap_acc,
                parent_i = cap_i
            }
            success, index, new_acc.n
                = matcher(subject, index, new_acc, 1, state)
            if success then
                -- dprint("\n\nXXXX captured: start:"..new_acc.start.." finish: "..index.."\n")
                new_acc.finish = index
                cap_acc[cap_i] = new_acc
                cap_i = cap_i + 1
            end
            return success, index, cap_i
        end
    end]]):gsub("XXXX", v), k.." compiler")(compile)
end


compilers["Carg"] = function (pt, ccache)
    local n = pt.aux
    return function (subject, index, cap_acc, cap_i, state)
        if state.args.n < n then error("reference to absent argument #"..n) end
        cap_acc[cap_i] = {
            type = "value",
            value = state.args[n],
            start = index,
            finish = index
        }
        return true, index, cap_i + 1
    end
end


compilers["Cb"] = function (pt, ccache)
    local tag = pt.aux
    return function (subject, index, cap_acc, cap_i, state)
         -- dprint("Cb       ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
         -- dprint("TAG: " .. ((state.tags[tag] or {}).type or "NONE"))
        cap_acc[cap_i] = {
            type = "Cb",
            start = index,
            finish = index,
            parent = cap_acc,
            parent_i = cap_i,
            tag = tag
        }
        return true, index, cap_i + 1
    end
end


compilers["Cc"] = function (pt, ccache)
    local values = pt.aux
    return function (subject, index, cap_acc, cap_i, state)
        cap_acc[cap_i] = {
            type = "values",
            values = values,
            start = index,
            finish = index,
            n = values.n
        }
        return true, index, cap_i + 1
    end
end


compilers["Cp"] = function (pt, ccache)
    return function (subject, index, cap_acc, cap_i, state)
        cap_acc[cap_i] = {
            type = "value",
            value = index,
            start = index,
            finish = index
        }
        return true, index, cap_i + 1
    end
end


compilers["Ctag"] = function (pt, ccache)
    local matcher, tag = compile(pt.pattern, ccache), pt.aux
    return function (subject, index, cap_acc, cap_i, state)
        local new_acc, success = {
            type = "Cg",
            start = index,
            Ctag = tag,
            parent = cap_acc,
            parent_i = cap_i
        }
        success, new_acc.finish, new_acc.n
            = matcher(subject, index, new_acc, 1, state)
        if success then
            cap_acc[cap_i] = new_acc
        end
        return success, new_acc.finish, cap_i + 1
    end
end


compilers["/zero"] = function (pt, ccache)
    local matcher = compile(pt.pattern, ccache)
    return function (subject, index, cap_acc, cap_i, state)
        local success, nindex = matcher(subject, index, {type = "discard"}, 1, state)
        return success, nindex, cap_i
    end
end


local function pack_Cmt_caps(i,...) return i, t_pack(...) end

compilers["Cmt"] = function (pt, ccache)
    local matcher, func = compile(pt.pattern, ccache), pt.aux
    return function (subject, index, cap_acc, cap_i, state)
        local tmp_acc = {
            type = "insert",
            parent = cap_acc,
            parent_i = cap_i
        }
        local success, nindex, tmp_i = matcher(subject, index, tmp_acc, 1, state)

        if not success then return false, index, cap_i end
        -- print("# @ # %%% - Cmt EVAL", index, tmp_acc.n ~= 0)

        local captures, mt_cap_i
        if tmp_i == 1 then
            captures, mt_cap_i = {s_sub(subject, index, nindex - 1)}, 2
        else
            tmp_acc.n = tmp_i
            captures, mt_cap_i = evaluate(tmp_acc, subject, nindex)
        end

        local nnindex, values = pack_Cmt_caps(
            func(subject, nindex, t_unpack(captures, 1, mt_cap_i - 1))
        )

        if not nnindex then return false, index, cap_i end

        if nnindex == true then nnindex = nindex end

        if type(nnindex) == "number"
        and index <= nnindex and nnindex <= #subject + 1
        then
            if #values > 0 then
                cap_acc[cap_i] = {
                    type = "values",
                    values = values,
                    start = index,
                    finish = nnindex,
                    n = values.n
                }
                cap_i = cap_i + 1
            end
        elseif type(nnindex) == "number" then
            error"Index out of bounds returned by match-time capture."
        else
            error("Match time capture must return a number, a boolean or nil"
                .." as first argument, or nothing at all.")
        end
        return true, nnindex, cap_i
    end
end


------------------------------------------------------------------------------
------------------------------------  ,-.  ,--. ,-.     ,--. ,--. ,--. ,--. --
--- Other Patterns                    |  | |  | |  | -- |    ,--| |__' `--.
--                                    '  ' `--' '  '    `--' `--' |    `--'


compilers["string"] = function (pt, ccache)
    local S = pt.aux
    local N = #S
    return function(subject, index, cap_acc, cap_i, state)
         -- dprint("String    ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
        local in_1 = index - 1
        for i = 1, N do
            local c
            c = s_byte(subject,in_1 + i)
            if c ~= S[i] then
         -- dprint("%FString    ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
                return false, index, cap_i
            end
        end
         -- dprint("%SString    ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
        return true, index + N, cap_i
    end
end


compilers["char"] = function (pt, ccache)
    return load(([[
        local s_byte = ...
        return function(subject, index, cap_acc, cap_i, state)
             -- dprint("Char    ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            local c, nindex = s_byte(subject, index), index + 1
            if c ~= __C0__ then
                return false, index, cap_i
            end
            return true, nindex, cap_i
        end]]):gsub("__C0__", tostring(pt.aux)))(s_byte)
end


local
function truecompiled (subject, index, cap_acc, cap_i, state)
     -- dprint("True    ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
    return true, index, cap_i
end
compilers["true"] = function (pt)
    return truecompiled
end


local
function falsecompiled (subject, index, cap_acc, cap_i, state)
     -- dprint("False   ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
    return false, index, cap_i
end
compilers["false"] = function (pt)
    return falsecompiled
end


local
function eoscompiled (subject, index, cap_acc, cap_i, state)
     -- dprint("EOS     ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
    return index > #subject, index, cap_i
end
compilers["eos"] = function (pt)
    return eoscompiled
end


local
function onecompiled (subject, index, cap_acc, cap_i, state)
     -- dprint("One     ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
    local char, nindex = s_byte(subject, index), index + 1
    if char
    then return true, nindex, cap_i
    else return false, index, cap_i end
end

compilers["one"] = function (pt)
    return onecompiled
end


compilers["any"] = function (pt)
    local N = pt.aux
    if N == 1 then
        return onecompiled
    elseif not charset.binary then
        return function(subject, index, cap_acc, cap_i, state)
             -- dprint("Any UTF-8",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            local n, c, nindex = N
            while n > 0 do
                c, nindex = s_byte(subject, index), index + 1
                if not c then
                     -- dprint("%FAny    ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
                    return false, index, cap_i
                end
                n = n -1
            end
             -- dprint("%SAny    ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            return true, nindex, cap_i
        end
    else -- version optimized for byte-width encodings.
        N = pt.aux - 1
        return function(subject, index, cap_acc, cap_i, state)
             -- dprint("Any byte",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            local n = index + N
            if n <= #subject then
                -- dprint("%SAny    ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
                return true, n + 1, cap_i
            else
                 -- dprint("%FAny    ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
                return false, index, cap_i
            end
        end
    end
end


do
    local function checkpatterns(g)
        for k,v in pairs(g.aux) do
            if not LL_ispattern(v) then
                error(("rule 'A' is not a pattern"):gsub("A", tostring(k)))
            end
        end
    end

    compilers["grammar"] = function (pt, ccache)
        checkpatterns(pt)
        local gram = map_all(pt.aux, compile, ccache)
        local start = gram[1]
        return function (subject, index, cap_acc, cap_i, state)
             -- dprint("Grammar ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            t_insert(state.grammars, gram)
            local success, nindex, cap_i = start(subject, index, cap_acc, cap_i, state)
            t_remove(state.grammars)
             -- dprint("%Grammar ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            return success, nindex, cap_i
        end
    end
end

compilers["behind"] = function (pt, ccache)
    local matcher, N = compile(pt.pattern, ccache), pt.aux
    return function (subject, index, cap_acc, cap_i, state)
         -- dprint("Behind  ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
        if index <= N then return false, index, cap_i end

        local success = matcher(subject, index - N, {type = "discard"}, cap_i, state)
        return success, index, cap_i
    end
end

compilers["range"] = function (pt)
    local ranges = pt.aux
    return function (subject, index, cap_acc, cap_i, state)
         -- dprint("Range   ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
        local char, nindex = s_byte(subject, index), index + 1
        for i = 1, #ranges do
            local r = ranges[i]
            if char and r[char]
            then return true, nindex, cap_i end
        end
        return false, index, cap_i
    end
end

compilers["set"] = function (pt)
    local s = pt.aux
    return function (subject, index, cap_acc, cap_i, state)
             -- dprint("Set, Set!",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
        local char, nindex = s_byte(subject, index), index + 1
        if s[char]
        then return true, nindex, cap_i
        else return false, index, cap_i end
    end
end

-- hack, for now.
compilers["range"] = compilers.set

compilers["ref"] = function (pt, ccache)
    local name = pt.aux
    local ref
    return function (subject, index, cap_acc, cap_i, state)
         -- dprint("Reference",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
        if not ref then
            if #state.grammars == 0 then
                error(("rule 'XXXX' used outside a grammar"):gsub("XXXX", tostring(name)))
            elseif not state.grammars[#state.grammars][name] then
                error(("rule 'XXXX' undefined in given grammar"):gsub("XXXX", tostring(name)))
            end
            ref = state.grammars[#state.grammars][name]
        end
        -- print("Ref",cap_acc, index) --, subject)
        return ref(subject, index, cap_acc, cap_i, state)
    end
end



-- Unroll the loop using a template:
local choice_tpl = [[
            success, index, cap_i = XXXX(subject, index, cap_acc, cap_i, state)
            if success then
                 -- dprint("%SChoice   ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
                return true, index, cap_i
            end]]
compilers["choice"] = function (pt, ccache)
    local choices, n = map(pt.aux, compile, ccache), #pt.aux
    local names, chunks = {}, {}
    for i = 1, n do
        local m = "ch"..i
        names[#names + 1] = m
        chunks[ #names  ] = choice_tpl:gsub("XXXX", m)
    end
    local compiled = t_concat{
        "local ", t_concat(names, ", "), [[ = ...
        return function (subject, index, cap_acc, cap_i, state)
             -- dprint("Choice   ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            local success
            ]],
            t_concat(chunks,"\n"),[[
             -- dprint("%FChoice   ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            return false, index, cap_i
        end]]
    }
    -- print(compiled)
    return load(compiled, "Choice")(t_unpack(choices))
end



local sequence_tpl = [[
             -- dprint("XXXX", nindex, cap_acc, new_i, state)
            success, nindex, new_i = XXXX(subject, nindex, cap_acc, new_i, state)
            if not success then
                 -- dprint("%FSequence",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
                return false, index, cap_i
            end]]
compilers["sequence"] = function (pt, ccache)
    local sequence, n = map(pt.aux, compile, ccache), #pt.aux
    local names, chunks = {}, {}
    -- print(n)
    -- for k,v in pairs(pt.aux) do print(k,v) end
    for i = 1, n do
        local m = "seq"..i
        names[#names + 1] = m
        chunks[ #names  ] = sequence_tpl:gsub("XXXX", m)
    end
    local compiled = t_concat{
        "local ", t_concat(names, ", "), [[ = ...
        return function (subject, index, cap_acc, cap_i, state)
             -- dprint("Sequence",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            local nindex, new_i, success = index, cap_i
            ]],
            t_concat(chunks,"\n"),[[
             -- dprint("%SSequence",cap_acc, cap_acc and cap_acc.type or "'nil'", new_i, index, state) --, subject)
             -- dprint("NEW I:",new_i)
            return true, nindex, new_i
        end]]
    }
    -- print(compiled)
   return load(compiled, "Sequence")(t_unpack(sequence))
end


compilers["at most"] = function (pt, ccache)
    local matcher, n = compile(pt.pattern, ccache), pt.aux
    n = -n
    return function (subject, index, cap_acc, cap_i, state)
         -- dprint("At most   ",cap_acc, cap_acc and cap_acc.type or "'nil'", index) --, subject)
        local success = true
        for i = 1, n do
            success, index, cap_i = matcher(subject, index, cap_acc, cap_i, state)
        end
        return true, index, cap_i
    end
end

compilers["at least"] = function (pt, ccache)
    local matcher, n = compile(pt.pattern, ccache), pt.aux
    if n == 0 then
        return function (subject, index, cap_acc, cap_i, state)
            -- [[DBG]] print("At least 0 ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            local success = true
            -- [[DBG]] local N = 1
            while success do
                -- [[DBG]] print("    rep "..N,cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state)
                -- [[DBG]] N=N+1
                success, index, cap_i = matcher(subject, index, cap_acc, cap_i, state)
            end
            return true, index, cap_i
        end
    elseif n == 1 then
        return function (subject, index, cap_acc, cap_i, state)
            -- [[DBG]] print("At least 1 ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            local success = true
            success, index, cap_i = matcher(subject, index, cap_acc, cap_i, state)
            if not success then return false, index, cap_i end
            -- [[DBG]] local N = 1
            while success do
                -- [[DBG]] ("    rep "..N,cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state)
                -- [[DBG]] N=N+1
                success, index, cap_i = matcher(subject, index, cap_acc, cap_i, state)
            end
            return true, index, cap_i
        end
    else
        return function (subject, index, cap_acc, cap_i, state)
            -- [[DBG]] print("At least "..n.." ",cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state) --, subject)
            local success = true
            for i = 1, n do
                success, index, cap_i = matcher(subject, index, cap_acc, cap_i, state)
                if not success then return false, index, cap_i end
            end
            -- [[DBG]] local N = 1
            while success do
                -- [[DBG]] print("    rep "..N,cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state)
                -- [[DBG]] N=N+1
                success, index, cap_i = matcher(subject, index, cap_acc, cap_i, state)
            end
            return true, index, cap_i
        end
    end
end

compilers["unm"] = function (pt, ccache)
    -- P(-1)
    if pt.ptype == "any" and pt.aux == 1 then
        return eoscompiled
    end
    local matcher = compile(pt.pattern, ccache)
    return function (subject, index, cap_acc, cap_i, state)
         -- dprint("Unm     ", cap_acc, cap_acc and cap_acc.type or "'nil'", cap_i, index, state)
        -- Throw captures away
        local success, _, _ = matcher(subject, index, {type = "discard", parent = cap_acc, parent_i = cap_i}, 1, state)
        return not success, index, cap_i
    end
end

compilers["lookahead"] = function (pt, ccache)
    local matcher = compile(pt.pattern, ccache)
    return function (subject, index, cap_acc, cap_i, state)
         -- dprint("Lookahead", cap_acc, cap_acc and cap_acc.type or "'nil'", index, cap_i, state)
        -- Throw captures away
        local success, _, _ = matcher(subject, index, {type = "discard", parent = cap_acc, parent_i = cap_i}, 1, state)
         -- dprint("%Lookahead", cap_acc, cap_acc and cap_acc.type or "'nil'", index, cap_i, state)
        return success, index, cap_i
    end
end

end

--                   The Romantic WTF public license.
--                   --------------------------------
--                   a.k.a. version "<3" or simply v3
--
--
--            Dear user,
--
--            The LuLPeg library
--
--                                             \
--                                              '.,__
--                                           \  /
--                                            '/,__
--                                            /
--                                           /
--                                          /
--                       has been          / released
--                  ~ ~ ~ ~ ~ ~ ~ ~       ~ ~ ~ ~ ~ ~ ~ ~
--                under  the  Romantic   WTF Public License.
--               ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~`,´ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
--               I hereby grant you an irrevocable license to
--                ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
--                  do what the gentle caress you want to
--                       ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
--                           with   this   lovely
--                              ~ ~ ~ ~ ~ ~ ~ ~
--                               / thing...
--                              /  ~ ~ ~ ~
--                             /    Love,
--                        #   /      '.'
--                        #######      ·
--                        #####
--                        ###
--                        #
--
--            -- Pierre-Yves
--
--
--            P.S.: Even though I poured my heart into this work,
--                  I _cannot_ provide any warranty regarding
--                  its fitness for _any_ purpose. You
--                  acknowledge that I will not be held liable
--                  for any damage its use could incur.
