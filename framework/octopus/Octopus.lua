---@v 1.1.5
---@class Octopus
---@description Octopus API库，提供在游戏中创建UI、管理数据、处理事件等一系列功能。
Octopus = {
    ---@class Octopus.logic
    ---@description 包含各种通用的逻辑和数据处理函数。
    logic = {
        --- 检查一个点是否在指定的矩形区域内（函数未实现）。
        ---@param axis any 待检查的轴或点
        ---@param x1 number 矩形区域坐标点1的x值
        ---@param y1 number 矩形区域坐标点1的y值
        ---@param x2 number 矩形区域坐标点2的x值
        ---@param y2 number 矩形区域坐标点2的y值
        ---@todo 此函数当前为空，需要实现具体逻辑。
        axis_square = function (axis,x1,y1,x2,y2)

            
        end,
        --- 将一个table的value转换为按0开始的数字字符串为key的table。
        ---@param table table 待转换的表。
        ---@return table 转换后的表，键为 "0", "1", "2", ...。
        indexput = function (table)
            local j = 0
            local tb = {}
            for i,v in pairs(table) do
                tb[tostring(j)] = v
                j = j + 1
            end
            return tb
        end,
        --- 检查表中是否存在指定的值。
        ---@param table table 要搜索的表。
        ---@param obj any 要查找的值。
        ---@return boolean 如果找到值，返回 true，否则返回 false。
        conclude = function (table,obj) --是否有此值
    
            for i,v in pairs(table) do
    
                if v == obj then
                    return true
                end
    
            end
    
            return false
    
    
    
        end,
        --- 检查表中是否存在指定的键。
        ---@param table table 要搜索的表。
        ---@param key any 要查找的键。
        ---@return boolean 如果找到键，返回 true，否则返回 false。
        haskey = function (table,key)--是否有此键
            for i,v in pairs(table) do
                if tostring(key) == tostring(i) then
                    return true
                end
    
            end
            return false
    
    
        end,
        --- 将表中所有的值（包括嵌套表）设置为指定的值。
        ---@param table table 要操作的表。
        ---@param value any 要设置的新值。
        ---@return table 修改后的表。
        allset = function(table,value)
    
            for i,v in pairs(table)do
                if type(i) == "table" then
                    Octopus.logic.allset(table,value)
                else
                    table[i] = value
                end
            end
    
            return table
    
        end ,
        --- 检查表是否为空。
        ---@param tbl table 要检查的表。
        ---@return boolean 如果表为空，返回 true，否则返回 false。
        isEmpty = function (tbl)
            if next(tbl) ~= nil then
                return false
            else
                return true
            end
        end,
        --- 将一个 Lua 表序列化为自定义格式的字符串。
        --- 格式为：`{[key1] = $value1^,[key2] = $value2^}`.
        --- 对于嵌套的表，会进行递归序列化。
        --- @warning 键和值中不应包含 `"` `[` `]` `$` `^` 等特殊字符。
        ---@param tb table 要序列化的表。
        ---@return string 序列化后的字符串。
        tostring = function ( tb )
    
            --禁止使用以下字符：" [ ] $ ^
    
            local str = "{"
    
            for i,v in pairs(tb) do
    
                if type(v) == "string" then
    
                    str = str.."["..tostring(i).."] = ".."$"..v.."^"..","
                
                elseif type(v) == "table" then
    
                    str = str.."["..tostring(i).."] = "..Octopus.logic.tostring(v)..","
    
                else
    
                    str = str.."["..tostring(i).."] = ".."$"..tostring(v).."^"..","
                end
    
            end
    
            str = str.."}"
    
            return str
    
            --[[
                [key] = $value$
            ]]
    
    
    
        end,
        
        --- 将 `Octopus.logic.tostring` 生成的字符串反序列化为 Lua 表。
        ---@param tstring string 要反序列化的字符串。
        ---@param runargs table? 内部使用的递归参数。
        ---@return table 反序列化后的表。
        strtotable = function (tstring,runargs)
    
            local function wordstotable(str) --将字符串拆开，每个字符表内的一个元素。
                local i = 0
                local tbl = {}
                while i<= string.len(str) do
                    i = i+1
                    local tmp = string.sub(str,i,i)
                    tbl[i] = tmp
    
                end
                return tbl
            end
    
    
    
            tstring = string.sub(tstring,2,tstring.len(tstring)-1)
    
            local onkeytyping = false
            local onvaluetyping = false
            local onmorestrtyping = false
    
            local tbl = {}
    
            local count_key = 0
    
            local tempkey = ""
    
            local tempfield = ""
    
            local sontableamount = 0
    
            if type(runargs) == "nil" then
                runargs = {
    
                    tablelevel = 1,
                    tableamount = 0,
    
                }
            end
    
            local level = "【第 "..tostring(runargs["tablelevel"]).." 层】"
    
            --Logger.log(level.."开始处理，要处理的字符串："..tstring)
    
    
    
    
    
            for i,v in pairs(wordstotable(tstring)) do
    
                --Logger.log(level.."一次新循环，onkeytyping = "..tostring(onkeytyping).."| onvaluetyping = "..tostring(onvaluetyping).."| onmorestrtyping = "..tostring(onmorestrtyping).."| count_key = "..tostring(count_key).."| tempfield = "..tempfield.."| 已有发现子表数量 = " ..tostring(sontableamount))
    
                if tostring(v) == "{" then
    
                    if sontableamount == 0 and onvaluetyping == false then
    
    
    
                        onmorestrtyping = true
    
                        --Logger.log(level.."开始处理一个表中表")
    
                    end
    
                end
    
    
    
    
                if onkeytyping == false or onvaluetyping == false or onmorestrtyping  == false then
    
    
                    if tostring(v) == "[" and onmorestrtyping == false then
    
                        if count_key == 0 then
    
                            --Logger.log(level.."开始处理一个键")
    
                            onkeytyping = true
    
                        end
    
    
    
    
                    elseif tostring(v) == "$" and onmorestrtyping == false then
    
                        --Logger.log(level.."开始处理一个值")
    
                        onvaluetyping = true
    
                    end
    
                end
                if onkeytyping  == true and onvaluetyping == false and onmorestrtyping == false then
    
                    if tostring(v) == "]" then
    
                        tbl[tempfield] = "NOVALUE"
    
                        --Logger.log(level.."已完成储存一个键："..tempfield)
    
                        count_key = count_key + 1
    
                        --Logger.log(level.."现有的键数量："..tostring(count_key))
    
                        tempkey = tempfield
    
                        --Logger.log(level.."临时的键值："..tempkey)
    
                        tempfield = ""
    
                        --Logger.log(level.."（键）tempfield清零")
    
                        onkeytyping = false
    
                    else
                        if tostring(v) ~= "[" then
    
                        tempfield = tempfield..tostring(v)
                        --Logger.log(level.."（键）tempfield被写为"..tempfield)
                        end
                    end
                end
    
                if onvaluetyping == true and onkeytyping == false and onmorestrtyping == false then
    
                    if tostring(v) == "^" then
    
                        tbl[tempkey] = tempfield
    
                        --Logger.log(level.."已完成储存一个值："..tempfield)
    
                        count_key = count_key - 1
    
                        --Logger.log(level.."现有的键数量："..tostring(count_key))
    
                        tempkey = ""
    
                        tempfield = ""
    
                        --Logger.log(level.."（值）tempfield清零")
    
                        onvaluetyping = false
    
                    else
    
                        if tostring(v) ~= "$" then
    
    
    
                        tempfield = tempfield..tostring(v)
                        --Logger.log(level.."（值）tempfield被写为"..tempfield)
                        end
                    end
                end
    
    
    
    
                if onmorestrtyping == true then
    
    
    
    
    
                    if tostring(v) == "{" then
                        sontableamount = sontableamount + 1
    
                        tempfield = tempfield..tostring(v)
                    end
    
    
    
                    if tostring(v) == "}"  then
    
                        --Logger.log(level.."}处理中，目前有子表："..tostring(sontableamount))
    
    
                        if tonumber(sontableamount) == 1 then
    
    
    
                            tempfield = tempfield..tostring(v)
    
                            runargs["tablelevel"] = runargs["tablelevel"] + 1
    
    
    
    
                            local temptable = Octopus.logic.strtotable(tempfield,runargs)
    
                            runargs["tablelevel"] = runargs["tablelevel"] - 1
    
                            --Logger.log(level.."已完成处理一个嵌套表！")
    
                            tbl[tempkey] = temptable
    
                            count_key = count_key - 1
    
                            tempfield = ""
    
                            sontableamount = sontableamount - 1
    
    
    
                            --Logger.log(level.."（表）tempfield清零")
    
                            onmorestrtyping = false
    
                        else
    
                            tempfield = tempfield..tostring(v)
    
                            sontableamount = sontableamount - 1
    
                            --Logger.log(level.."已录入完一个子表")
    
    
    
    
                        end
                    end
    
    
    
                    if tostring(v) ~= "{" and tostring(v) ~= "}" then
    
    
    
    
    
    
    
                        --Logger.log(level.."（表）tempfield被写为"..tempfield)
    
                        tempfield = tempfield..tostring(v)
    
                        --Logger.log(level.."tempfield被写为"..tempfield)
    
    
                    end
    
    
    
    
                end
    
    
            end
    
            --Logger.log(level.."已返回最终结果。")
    
            return tbl
    
    
    
        end,
        
        --- 使用模板表 `targettb` 的键值对来补全 `tb` 表。
        --- 如果 `tb` 中缺少 `targettb` 中的某个键，则将该键值对复制到 `tb` 中。此过程会递归处理嵌套的表。
        ---@param tb table 需要被补全的表。
        ---@param targettb table 模板表。
        ---@param temp table? 内部递归使用的参数。
        ---@return table 补全后的表。
        complete = function ( tb ,targettb,temp)---@targettb为模板表，按照targettb将tb中不包含的键一一赋值
            if temp == nil then
                model = targettb
            else
                model = temp
            end
    
    
            for i , v in pairs(model) do
    
                if type(v) ~= "table" and type(tb[i]) == nil then
    
                    tb[i] = model[i]
                end
    
                if type(v) == "table" and type(tb[i]) == "nil" then
    
                    tb[i] = model[i]
                end
    
                    
    
                if type(v) == "table" and type(tb[i]) == "table" then
    
                    tb[i] = Octopus.logic.complete(tb[i],targettb,v)
                end
    
    
    
            end
    
            return tb
    
        end,
        
        --- 通过 `pairs` 迭代计算表中键值对的数量。
        ---@param table table 要计算长度的表。
        ---@return number 表中的元素数量。
        length = function (table)
            
            local count = 0
            for i,v in pairs(table) do
                count = count + 1
            end
            return count
            
    
        end,
        --- 重新索引一个表，使其键变为从 "1" 开始的数字字符串。
        ---@param table table 要重新索引的表。
        ---@return table 重新索引后的新表，键为 "1", "2", "3", ...。
        sortkeybynumber = function (table)
            local c = 0
            local temp = {}
            for i,v in pairs(table) do
                c = c + 1
                temp[tostring(c)] = v
            end
            return temp
        end,

        --- 向一个使用字符串数字作为索引的类数组表中追加一个元素。
        ---@param table table 目标表。
        ---@param object any 要追加的元素。
        append = function (table,object)
            local len = Octopus.logic.length(table)
            table[tostring(len)] = object
        end,
        --- 从一个使用字符串数字作为索引的类数组表中删除一个元素，并重新整理索引。
        ---@param table table 目标表。
        ---@param key string|number 要删除的元素的键。
        remove = function (table,key)
            table[tostring(key)] = nil
            local j = 0
            local table2 = {}
            for i,v in pairs(table) do
                table2[tostring(j)] = v
                table[i] = nil
                j = j + 1
            end
            for i,v in pairs(table2) do
                table[i] =  v 
            end
            
        end,
        --- 根据值在表中查找对应的键。
        ---@param table table 要搜索的表。
        ---@param value any 要查找的值。
        ---@return any|nil 找到的键，如果未找到则返回 nil。
        getKeyByValue = function (table, value)
            for k, v in pairs(table) do
                if v == value then
                    return k
                end
            end
            return nil -- 如果没有找到对应的键，返回 nil
        end
    
    },
    ---@class Octopus.LOG
    ---@description 提供简单的日志记录功能。
    LOG = {
        --- 将文本追加到全局日志变量 `GLOBAL_LOG` 中。
        ---@param text string 要写入的日志文本。
        writelog = function (text)
            if GLOBAL_LOG == nil then
                GLOBAL_LOG = ""
            end
            
            GLOBAL_LOG = GLOBAL_LOG..text.."\n"
        end,
        --- 使用 `Octopus.GUI.Menu.open` 显示当前存储的全局日志。
        showlog = function ()
            Octopus.GUI.Menu.open(GLOBAL_LOG)
        end,
        --- 清空全局日志。
        clearlog = function ()
            GLOBAL_LOG = ""
            
        end,
        --- 显示一条错误信息。
        ---@param text string 错误信息。
        error = function (text)
            effect("text",args,'error:'..text,"4")
            effect("text",args,'error:'..text,"1")
        end
    },
    ---@class Octopus.Assests
    ---@description 存储游戏内的资源路径、ID和颜色等静态数据。
    Assests = {
        ---@class Octopus.Assests.PICTURES
        ---@description 常用图片资源。
        PICTURES = {
            HEADLINE = "{img:Interface\\QUESTFRAME\\UI-HorizontalBreak:312:64}"
        },
        ---@class Octopus.Assests.SoundLibrary
        ---@description 常用音效库。
        SoundLibrary = {
    
            UI = {
        
        
                CANCEL = 44310,
                JIHESHI = 47615,
                DIG = 193991,
                BEAT = 116826,
                MACHINE = 138317,
                GEAR = 138318,
                MAGIC = 12988,
                FLAME = 145118,
                CLICK = 169567,
                ATTACK = 177165,
                SUCCESS = 165970
        
            }
        
        },
        
        ---@class Octopus.Assests.Icons
        ---@description 常用图标资源。
        Icons = {
    
            ['mage'] = '{icon:classicon_mage:16}',
            ['warrior'] = '{icon:classicon_warrior:16}',
            ['warlock'] = '{icon:classicon_warlock:16}',
            ['deathknight'] = '{icon:classicon_deathknight:16}',
            ['demonhunter'] = '{icon:classicon_demonhunter:16}',
            ['hunter'] = '{icon:classicon_hunter:16}',
            ['monk'] = '{icon:classicon_monk:16}',
            ['paladin'] = '{icon:classicon_paladin:16}',
            ['priest'] = '{icon:classicon_priest:16}',
            ['rogue'] = '{icon:classicon_rogue:16}',
            ['shaman'] = '{icon:classicon_shaman:16}',
            ['druid'] = '{icon:classicon_druid:16}',
            ['others'] = '{icon:ability_xaril_masterpoisoner_red:16}'
    
        },
        ---@class Octopus.Assests.Colour
        ---@description 常用颜色值和工具。
        Colour = {
            --- 为文本添加颜色标记。
            ---@param text string 要着色的文本。
            ---@param colour string 16进制颜色代码字符串 (例如 "FF0500")。
            ---@return string 包含颜色标记的文本。
            paint = function (text,colour)
    
                text = "{col:"..colour.."}"..text.."{/col}"
    
                return text
                
            end,
    
            GREY = "878787",
            RED = "FF0500",
            DARK_RED = "680200",
            LIGHT_GREEN = "44FF56",
            DARK_BLUE = "020082",
    
    
        }
        
            
        },

    ---@class Octopus.GUI
    ---@description 图形用户界面（GUI）相关的功能，主要用于构建和管理菜单。
    GUI = {
        ---@class Octopus.GUI.Builder
        ---@description 用于以编程方式构建菜单的工具集。
        Builder = {
            --- 创建一个新的菜单结构表。
            ---@param height integer? 菜单的行数。如果为 nil 或 0，则行数不固定。
            ---@return table 一个新的菜单结构表。
            new_menu = function (height)
                local menu = {}
                menu["lines"] = {}
                height = height or 0
                for i=0,height-1 do
                    menu["lines"][tostring(i)] = Octopus.GUI.Builder.new_line()
                end
                menu["settings"] = {
                    ["CutIfOutSize"] = "FALSE",
                    ["MenuHeight"] = 768,
                    ["MenuWidth"] = 768

                }
                return menu
            end,
            --- 创建一个新的行结构表。
            ---@return table 一个新的行结构表。
            new_line = function ()
                return {
                    ["settings"] = {
                        ["BASE_COLOUR"] = "000000",
                        ["FONT"] = "h1",
                        ["LOCATION"] = "c",
                        ["IS_IMAGE"] = "FALSE"
                    },
                    ["objects"] = {
                        
                    }
                }
            end,
            --- 创建一个菜单对象。
            --- `Aargs` 参数说明:
            --- - `text`: `{ [0] = "文本内容", [1] = "颜色" }`
            --- - `link`: `{ [0] = "显示文本", [1] = "颜色", [2] = "链接脚本" }`
            --- - `image`: `{ [0] = "图片URL", [1] = 高度, [2] = 宽度 }`
            --- - `icon`: `{ [0] = "图标URL", [1] = 尺寸 }`
            ---@param type string 对象类型 ("text", "link", "image", "icon")。
            ---@param Aargs table 对象的参数表。
            ---@param line table? (未使用) 所在的行。
            ---@return table 一个新的对象结构表。
            new_object = function (type,Aargs,line)
                if type == "text" then
                   
                    return {
                        ["type"] = "text",
                        ["text"] = Aargs["0"] or "",
                        ["colour"] = Aargs["1"] or "000000",
                    }
                elseif type == "link" then
                    return {
                        ["type"] = "link",
                        ["text"] = Aargs["0"] or "",
                        ["colour"] = Aargs["1"] or "000000",
                        ["link"] =Aargs["2"] or "NOLINK"
                                        }
                elseif type == "image" then
                    return {
                        ["type"] = "image",
                        ["url"] = Aargs["0"] or "Interface\\GLUES\\LOADINGSCREENS\\Expansion07\\Main\\Loadscreen_NzothRaid_Visions",
                        ["height"] = Aargs["1"] or 64,
                        ["width"] = Aargs["2"] or 64,
                    }
                elseif type == "icon" then
                    return {
                        ["type"] = "icon",
                        ["url"] = Aargs["0"] or "text",
                        ["size"] = Aargs["1"] or 64,
                    }
                else
                    error("Invalid menu object type.")
                end
            end,

            --- 修改一个菜单对象的属性。
            ---@param object table 要修改的对象。
            ---@param key string|number 要设置的键。
            ---@param value any 要设置的值。
            object_set = function (object,key,value)
                object[key] = value
            end,
            --- 在行的指定位置插入一个菜单对象。
            ---@param line table 要插入对象的行。
            ---@param object table 要插入的对象。
            ---@param loc number? 插入位置的索引。如果为 nil，则追加到末尾（当前实现未处理nil）。
            line_insert = function (line,object,loc)
                if loc then
                    if loc < Octopus.logic.length(line["objects"]) then
                        local newtb = {};
                        local j = 0
                        for i=0,Octopus.logic.length(line["objects"]) -1 do
                            if tostring(loc) == i then
                                newtb[tostring(j)] = object

                                
                                j = j + 1
                                newtb[tostring(j)] = line['objects'][tostring(i)]
                            else
                                newtb[tostring(j)] = line['objects'][tostring(i)]

                            end
                            j = j +1
                        end
                        for k in pairs(line['objects']) do
                            line['objects'][k] = nil
                        end
                        for k in pairs(newtb) do
                            line['objects'][k] = newtb[k]
                        end
                        
                    else

                    end
                else

                end
                
            end,
            --- 替换行中指定位置的对象。
            ---@param line table 目标行。
            ---@param object table 新的对象。
            ---@param loc number|string 要替换的位置索引。
            line_replace = function (line,object,loc)
                line["objects"][tostring(loc)] = object
            end,
            --- 移除行中指定位置的对象。
            ---@param line table 目标行。
            ---@param loc number|string 要移除的位置索引。
            line_remove = function (line,loc)
                line["objects"][tostring(loc)] = nil
            end,
            ---@class Octopus.GUI.Builder.preset_menu
            ---@description 预设的菜单模板。
            preset_menu = {
                --- 创建一个预设的确认菜单结构表。
                ---@param ConfirmMessage string 确认信息的主标题。
                ---@param ConfirmLore string 确认信息的详细描述。
                ---@param ConfirmScript string "确定"按钮触发的脚本名称。
                ---@param ConfirmArgs string "确定"按钮触发的脚本参数。
                ---@param CancelScript string "取消"按钮触发的脚本名称。
                ---@param CancelArgs string "取消"按钮触发的脚本参数。
                ---@return table 一个预设的确认菜单结构表。
                confirmation = function (ConfirmMessage,ConfirmLore,ConfirmScript,ConfirmArgs,
                    CancelScript,CancelArgs)
                    local menu = Octopus.GUI.Builder.new_menu(3)
                    menu["lines"]["0"]["objects"]["0"] = 
                        Octopus.GUI.Builder.new_object("text",Octopus.logic.indexput({ConfirmMessage}))
                    
                    menu["lines"]["1"]["FONT"] = "h3"
                    menu["lines"]["1"]["objects"]["0"] = 
                        Octopus.GUI.Builder.new_object("text",Octopus.logic.indexput({ConfirmLore,"dc5a5a"}))
                    
                    menu["lines"]["2"]["objects"]["0"] = 
                        Octopus.GUI.Builder.new_object("link",Octopus.logic.indexput({"确定",
                        "444444",
                        "runner(scriptname="..ConfirmScript..",scriptargs="..ConfirmArgs.. ")"
                    }))
                    menu["lines"]["2"]["objects"]["1"] = 
                    Octopus.GUI.Builder.new_object("icon",Octopus.logic.indexput({"ability_paladin_judgementsofthejust","32"}))
                
                    menu["lines"]["2"]["objects"]["2"] = 
                    Octopus.GUI.Builder.new_object("link",Octopus.logic.indexput({"取消",
                    "444444",
                    "runner(scriptname="..CancelScript..",scriptargs="..CancelArgs.. ")"
                
                })
            )
                return menu
                    
                end
            },
            

            --- 将菜单结构表编译成游戏内可识别的格式化字符串。
            ---@param menu table 使用 `new_menu` 创建的菜单结构表。
            ---@return string 构建好的、用于显示的菜单字符串。
            build = function (menu)
                local menutext = ""
                for i=0,Octopus.logic.length(menu["lines"])-1 do
                    local line = menu["lines"][tostring(i)]
                        if line["settings"]["IS_IMAGE"] == "FALSE" then
                            menutext = menutext.."{"..line["settings"]["FONT"]..":" .. line["settings"]["LOCATION"] .. "}"
                            
                            for j=0,Octopus.logic.length(line["objects"])-1 do 
                                
                                local obj = line["objects"][tostring(j)]
                               
                                if obj["type"] == "text" then
                                    Octopus.LOG.writelog(tostring(obj["text"]))
                                    Octopus.LOG.showlog()
                                    menutext = menutext.. "{col:" .. obj["colour"] .. "}"
                                    ..obj["text"] 
                                    .."{/col}"
                                elseif obj["type"] == "link" then
                                    menutext = menutext.. "{col:" .. obj["colour"] .. "}"
                                    .. "{link*".. obj["link"] .."*"..obj["text"].."}" 
                                    
                                    .."{/col}"
                                elseif obj["type"] == "icon" then
                                    menutext = menutext .. "{icon"..":"..obj["url"]..":"..tostring(obj["size"]).."}"
                                end
                            end 
                            menutext = menutext.."{/"..line["settings"]["FONT"] .. "}"
                        else
                            local img = line['objects']["0"]
                            menutext = menutext .. "{img:"..img['url']..":"..tostring(img['width'])..":"..tostring(img["height"]).."}"

                        end

                        
                        
                end
                return menutext
            end,
        }

        ,
        ---@class Octopus.GUI.Menu
        ---@description 用于直接控制和显示菜单的接口。
        Menu = {
    
            --- 设置当前菜单的显示内容，但不立即显示。
            ---@param text string 要设置的菜单文本。
            set = function (text)
        
                setVar(args,"c","MenuText",text)
                
            end,
            --- 显示当前设置的菜单。会禁用菜单项。
            ---@param ... any (未使用) 可变参数。
            show = function (...)
                --Menu.close()
                Octopus.GUI.Menu.Config.MenuItem_UseAble("FALSE")
                effect("run_workflow",args,"c","open_menu")
            end,
            
            --- 显示当前菜单，但不触发关闭逻辑。
            show_without_close = function ()
                effect("run_workflow",args,"c","open_menu")
            end,
            
            --- 打开一个新菜单，但不记录到历史。
            ---@param text string 要打开并显示的菜单文本。
            open_without_close = function (text)
        
                setVar(args,"c","MenuText",text)
                Octopus.Data.save("OctopusOptions","MENU_RECORD_LATEST","FALSE")
                effect("run_workflow",args,"c","open_menu")
                
            end,
        
            --- 打开一个新菜单。会记录到最近菜单历史中。
            ---@param text string 要打开并显示的菜单文本。
            open = function (text)
        
                --Menu.close()
                setVar(args,"c","MenuText",text)
                Octopus.GUI.Menu.Config.MenuItem_UseAble("FALSE")
                Octopus.Data.save("OctopusOptions","MENU_RECORD_LATEST","TRUE")
                effect("run_workflow",args,"c","open_menu")
                
            end,
            --- 禁用"最近菜单"的记录功能。
            disable_record = function ()
                Octopus.Data.save("OctopusOptions","MENU_RECORD_LATEST","FALSE")
            end,
            
            --- 设置"最近菜单"的文本内容。
            ---@param text string 菜单文本。
            setlatest = function (text)
        
                setVar(args,"c","LatestMenu",text)
                
            end,
            
            --- 打开"最近菜单"。
            openlatest = function ()
        
                Octopus.GUI.Menu.open(getVar(args,"c","LatestMenu"))
                
            end,
            
            --- 关闭当前菜单。
            close = function ()
                if Octopus.Data.get_value("OctopusOptions","MENU_RECORD_LATEST")=="TRUE" then
                    Octopus.GUI.Menu.setlatest(getVar(args,"c","MenuText"))
                end
                Octopus.GUI.Menu.Config.MenuItem_UseAble("TRUE")
                
        
                effect("run_workflow",args,"c","close_menu")
            end,
            
            ---@class Octopus.GUI.Menu.linkinfotemplate
            ---@description 菜单链接信息的模板。
            linkinfotemplate = {
                
                scriptname = {
                ["1"] = 'DefaultLinkScript',
                ["2"] = 'DefaultLinkScript',
                ["3"] = 'DefaultLinkScript',
                ["4"] = 'DefaultLinkScript',
                ["5"] = 'DefaultLinkScript',
                ["6"] = 'DefaultLinkScript',},
        
                scriptargs = {        
                ["1"] = 'noargs',
                ["2"] = 'noargs',
                ["3"] = 'noargs',
                ["4"] = 'noargs',
                ["5"] = 'noargs',
                ["6"] = 'noargs',
                }
                
        
        
                
        
            },
            
            --- 设置菜单链接对应的脚本和参数。
            ---@param linkinfo table 链接信息表，格式: `{["scriptname"] = {["1"] = ...},["scriptargs"] = {...}}`
            LinkSetter = function(linkinfo)--传入一个表，{"scriptname" = {["1"] = ...},"scriptargs" = {...}}
        
                linkinfo = Octopus.logic.complete(linkinfo,Octopus.GUI.Menu.linkinfotemplate)
                for i , v in pairs(linkinfo["scriptname"]) do
                    setVar(args,"c","MenuScript_"..i,v)
                end  
                for i , v in pairs(linkinfo["scriptargs"]) do
                    setVar(args,"c","MenuArgs_"..i,v)
                end
                
            end,
            --- 为输入链接设置脚本和参数。
            ---@param linkinfo table 链接信息表。
            LinkSetter_input = function (linkinfo) --传入一个表，{"scriptname" = {["1"] = ...},"scriptargs" = {...}}
        
                linkinfo = Octopus.logic.complete(linkinfo,Octopus.GUI.Menu.linkinfotemplate)
                for i , v in pairs(linkinfo["scriptname"]) do
                    
                    setVar(args,"c","MenuScript_input"..i,v)
                end  
                for i , v in pairs(linkinfo["scriptargs"]) do
                    
                    setVar(args,"c","MenuArgs_input"..i,v)
                end
                
            end,
        
            ---@class Octopus.GUI.Menu.Config
            ---@description 菜单行为的配置选项。
            Config = {
                --- 设置一个菜单配置。
                ---@param text string 配置项名称。
                ---@param value any 配置项的值。
                set = function (text,value)
                    setVar(args,"c",text,value)
                end,
        
                --- 获取或设置菜单是否可关闭。
                ---@param text "TRUE"|"FALSE"|nil 如果提供，则设置该值；否则返回当前值。
                ---@return string|nil 当前是否可关闭的状态。
                CloseAble = function (text)
                    
                    if text == nil then
                        return getVar(args,"c","Menu_CloseAble")
                    else
                        Octopus.GUI.Menu.Config.set("Menu_CloseAble",text)
                    end
                end,
        
        
                --- 获取或设置菜单项是否可用。
                ---@param text "TRUE"|"FALSE"|nil 如果提供，则设置该值；否则返回当前值。
                ---@return string|nil 当前菜单项是否可用的状态。
                MenuItem_UseAble = function (text)
                    if text == nil then
                        return getVar(args,"c","MenuItem_UseAble")
                    else
                        Octopus.GUI.Menu.Config.set("MenuItem_UseAble",text)
                    end
                end,
        
                --- 获取或设置菜单是否处于"确认中"状态。
                ---@param text "TRUE"|"FALSE"|nil 如果提供，则设置该值；否则返回当前值。
                ---@return string|nil 当前是否处于确认中状态。
                Confirming = function (text)
                    if text == nil then
                        return getVar(args,"c","Menu_Confirming")
                    else
                        Octopus.GUI.Menu.Config.set("Menu_Confirming",text)
                    end
                end,
        
            },
        
            ---@class Octopus.GUI.Menu.Builder
            ---@description 用于快速构建特定功能菜单的工具。
            Builder = {
                
                --- 创建一个确认窗口。
                --- 会弹出一个确认菜单，并锁定菜单使其无法被关闭。
                ---@param confirmtype string 确认操作的类型或标题。
                ---@param descripe string 操作的详细描述。
                ---@param warns string 警告信息。
                ---@param scriptname string 用户点击"确定"后要执行的脚本名称。
                ---@param ... any 传递给脚本的参数。
                ---@return string 构建好的确认菜单文本。
                confirmation = function(confirmtype,descripe,warns,scriptname,...)
                --[[
                    会弹出一个确认菜单：
                    你确定要： confirmtype 吗？
                    descripe
                    warns
                    并锁定菜单使其无法被关闭
        
                ]]--
        
                    local menutext = "{img:Interface\\QUESTFRAME\\UI-HorizontalBreak:312:64}\n"
                    if type(confirmtype) ~= nil then
                        menutext = menutext.."{h1:c}你确定要：{col:670001} "..confirmtype.." {/col}吗？{/h1}\n"
                    end 
                    if type(descripe) ~= nil then
                        menutext = menutext.."{h2:c}"..descripe.."{/h2}\n"
                    end
                    if type(warns) ~= nil then
                        menutext = menutext.."{h3:c}{col:ff2800}"..warns.."{/col}{/h3}\n"
                    end
                    menutext = menutext.."{img:Interface\\QUESTFRAME\\UI-HorizontalBreak:312:64}{h1:c}{link*confirm*{icon:inv_misc_ticket_tarot_twistingnether_01:16}}{col:71ff50}{link*confirm*确定}".."\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t".."{/col}{col:BA2026}{link*cancel*取消}{/col}{link*cancel*{icon:70_inscription_deck_immortality:16}}{/h1}"
                    menutext = menutext.."\n"
                    setVar(args,"c","ScriptName",scriptname)
                    Octopus.GUI.Menu.Config.Confirming("TRUE")
        
                    return menutext
        
        
        
                end,
                
                --- 创建一个带分页的选择菜单。
                ---@param objects table 选项列表。每个选项是一个表，例如 `{text = "", scriptname = "", scriptargs = ""}`。
                ---@param lore string 菜单的说明文字。
                ---@param afterrun string 取消选择后要运行的脚本名称。
                choose = function (objects,lore,afterrun)--objtemplate = {["1"] = {text = "",scriptname = "",scriptargs = "",},}
                    local title = "{img:Interface\\QUESTFRAME\\UI-HorizontalBreak:312:64}{h1:c}请选择："..lore.."{/h1}{h2:c}\n"
                    local text = title
        
                    local o = ""
                    local c = 0
                    local pc = 0
                    local p = 1
                    local lc = 0
                    local pages = {}
                    pages["1"] = {                        
                        linksetter = {
                        scriptname = {},
                        scriptargs = {}
                    }}
                    
                    while c < Octopus.logic.length(objects) do
                        
                        c = c + 1
                        o = objects[tostring(c)] ---@class objtemplate
                        if pc < 5 then
                            pc = pc + 1
                            text = text .. o["text"] .. "{link*" .. "link"..tostring(pc) .. "*选择}\n"
                            lc = lc + 1
                            pages[tostring(p)]["linksetter"]["scriptname"][tostring(lc)] = "choose_selecetedvalue"
                            pages[tostring(p)]["linksetter"]["scriptargs"][tostring(lc)] = o["scriptargs"]
        
        
                            
                            
                        end
                        if pc == 5 or c + 1 > Octopus.logic.length(objects) then
                            
                            pc = 0
                            lc = 0
                            text = text .. "\n{link*choose.last*上一页} 第 "..tostring(p) .." 页 {link*choose.next*下一页}\n\n"
                            text = text ..Octopus.Assests.Colour.paint("{link*choose.cancel*取消选择}\n",Octopus.Assests.Colour.DARK_RED)
                            text = text .. "{/h2}{img:Interface\\QUESTFRAME\\UI-HorizontalBreak:312:64}"
                            
                            pages[tostring(p)]["text"] = text
                            text = title
                            p = p + 1
                            pages[tostring(p)] = {
                                linksetter = {
                                    scriptname = {},
                                    scriptargs = {}
                                }
                            }
                    end
                    setVar(args,"c","temp_choose_pages",Octopus.logic.tostring(pages))
                    Octopus.GUI.Menu.open(pages["1"]["text"])
                    Octopus.GUI.Menu.LinkSetter(pages["1"]["linksetter"])
                    setVar(args,"c","choose_afterrun",afterrun)
                    setVar(args,"c","choose_nowopenpage","1")
                    
        
                end
        
        
                end,
                --- 创建一个带分页的选择菜单（版本2）。
                ---@param objects table 选项列表。每个选项是一个表，例如 `{text = "", scriptname = "", scriptargs = ""}`。
                ---@param lore string 菜单的说明文字。
                ---@param afterrun string 取消选择后要运行的脚本名称。
                ---@param maxinpage integer? 每页最多显示的项目数，默认为5。
                choose2 = function (objects,lore,afterrun,maxinpage)--objtemplate = {["1"] = {text = "",scriptname = "",scriptargs = "",},}
                    local title = "{img:Interface\\QUESTFRAME\\UI-HorizontalBreak:312:64}{h1:c}请选择："..lore.."{/h1}{h2:c}\n"
                    local text = title
        
                    local o = ""
                    local c = 0
                    local pc = 0
                    local p = 1
                    local pages = {}
                    maxinpage = maxinpage or 5
                    pages["1"] = {}
                    
                    while c < Octopus.logic.length(objects) do
                        c = c + 1
                        o = objects[tostring(c)] ---@class objtemplate
                        if pc < maxinpage then
                            pc = pc + 1
                            text = text .. o["text"] .. "{link*" .. "runner(scriptname="..o["scriptname"]
                            ..",scriptargs="..o["scriptargs"]..")"
                            .."*选择}\n"
                        end
                        if pc == maxinpage or c + 1 > Octopus.logic.length(objects) then
                            
                            pc = 0
                            text = text .. "\n{link*runner(scriptname=choose_page,scriptargs=last)*上一页} 第 "..tostring(p) .." 页 {link*runner(scriptname=choose_page,scriptargs=next)*下一页}\n\n"
                            text = text ..Octopus.Assests.Colour.paint("{link*runner(scriptname=choose_cancel)*取消选择}\n",Octopus.Assests.Colour.DARK_RED)
                            text = text .. "{/h2}{img:Interface\\QUESTFRAME\\UI-HorizontalBreak:312:64}"
                            
                            pages[tostring(p)]["text"] = text
                            --nextpage
                            text = title
                            p = p + 1
                            pages[tostring(p)] = {}
                    end
                    Octopus.Data.save("temp_choose_pages",nil,pages)
                    Octopus.GUI.Menu.open(pages["1"]["text"])
                    setVar(args,"c","choose_nowopenpage","1")
                    setVar(args,"c","choose_afterrun",afterrun)
                    
        
                end
        
        
                end
        
        
        
        
                
        
            },
            --- 获取 `choose` 菜单的选择结果。
            ---@return any 选择的结果。
            choose_getvalue = function ()
                local a = getVar(args,"c","temp_choose_result")
                
                setVar(args,"c","temp_choose_result","cancel")
        
                return a
                
            end,

        
    },}
    ,
    ---@class Octopus.Data
    ---@description 提供基于游戏变量的持久化数据存储功能。数据以 "folder" 和 "name" 的形式组织。
    Data = {

        ---详见Octopus(Data Logic).png


        --- 删除一个 "文件夹" 及其所有内容。
        ---@param folder string "文件夹" 名称。
        delete_folder = function (folder)
            setVar(args,"c","."..folder,nil)
        end,
        
        --- 将数据保存到指定的 "文件夹" 中。数据会被序列化为字符串进行存储。
        ---@param folder string "文件夹"名称，即存储域的名称。
        ---@param name string|nil "文件"名称，即要保存的数据的键。如果为 nil，`value` 将直接覆盖整个 `folder`。
        ---@param value any 要保存的值。表和函数返回值会被转换为字符串。
        save = function (folder,name,value)
            --.foldername 储存一个表
            --使用get_value直接获取表中的一个值
            --如果name为nil，直接覆盖目录为value
            --如果name不为nil，则修改name的值
            local folderlist = Octopus.logic.strtotable(getVar(args,"c",".*folderlist"))
        
            local function hasregisteredfolder(foldername)
                local folderlist = Octopus.logic.strtotable(getVar(args,"c",".*folderlist"))        --带*号的是不开放式目录
                if folderlist ~= nil then
                    for i,v in pairs(folderlist) do
                        if v == foldername then
                            return true
                        end
                    end
                end
                return false
            end
        
            local function init()
                setVar(args,"c",".*folderlist","{}")
            end
        
            local function registerfolder(foldername)
                --{[1]=xxx}
                folderlist[#folderlist+1] = foldername
                setVar(args,"c",".*folderlist",Octopus.logic.tostring(folderlist))
                setVar(args,"c","."..foldername,"{}")
        
            end
        
            
            if tostring(getVar(args,"c",".*folderlist")) == "nil" then
                init()
            end
        
            --如果是value表就把它变成可储存字段
            if type(value) ~= "string" then
                if type(value) == 'number' then
                    value = tostring(value)
                elseif type(value) == 'function' then--函数是取返回值
                    value = value()
                end
            end
        
            
            if tostring(name) ~= 'nil' then
                local fd = Octopus.logic.strtotable(getVar(args,"c","."..folder))
---@diagnostic disable-next-line: need-check-nil
                fd[name] = value
                setVar(args,"c","."..folder,Octopus.logic.tostring(fd))
            else
                setVar(args,"c","."..folder,Octopus.logic.tostring(value))
            end
            
            if hasregisteredfolder(folder) then
                registerfolder(folder)
            end
        
            
        
        
            
        end,
        --- 从 "文件夹" 中获取一个值。
        ---@param folder string "文件夹"名称。
        ---@param name string "文件"名称。
        ---@return any|nil 存储的值。字符串会自动反序列化为表。如果找不到，返回 nil。
        get_value = function (folder,name)
            return Octopus.logic.strtotable(getVar(args,"c","."..folder))[name]
        end,
        --- 获取整个 "文件夹" 的内容。
        ---@param folder string "文件夹"名称。
        ---@return table|nil 整个 "文件夹" 的内容（已反序列化为表）。如果找不到，返回 nil。
        get_folder = function (folder)
        
            return Octopus.logic.strtotable(getVar(args,"c","."..folder))
        
            
    end,},
        --- 清除所有名称以 "temp_" 开头的临时数据文件夹。
        cleartemp = function ()
            for i ,folder_name in pairs(Octopus.Data.get_folder("*folderlist")) do
                if string.find(folder_name,"temp_") ~= nil then
                    Octopus.Data.save(folder_name,nil,nil)
                end
            end
        end,
        
    ---@class Octopus.Sound
    ---@description 音效播放相关功能。
    Sound = {
        --- 为玩家自己播放一个音效。
        ---@param soundID number 音效ID。
        playSoundSelf = function (soundID)
    
            effect("sound_id_self",args,nil,soundID)
            
        end
    
    },
    ---@class Octopus.Listener
    ---@description 一个事件监听器系统，用于响应游戏内的各种事件。
    Listener = {
        ---@class Octopus.Listener.types
        ---@description 支持的监听器事件类型。
        types = {
            "OnMessage_say","OnMessage_yell","OnMessage_emote"
            ,"OnMessage_raid","OnMessage_party","OnMessage_raidwarning",
            "OnMessage_guild","OnMessage_whisper","OnPlayerStartMove","Always"
        },
        ---@private
        --- 初始化监听器数据结构。
        __init = function ()

            local R_Listner = Octopus.Data.get_folder("RegisteredListener")
            if R_Listner == nil or R_Listner == {} or not R_Listner["OnMessage_say"] then
                R_Listner = {
                    OnMessage_say = {},
                    OnMessage_yell = {},
                    OnMessage_emote = {},
                    OnMessage_raid = {},
                    OnMessage_party = {},
                    OnMessage_raidwarning = {},
                    OnMessage_guild = {},
                    OnMessage_whisper = {},
                    OnPlayerStartMove = {},
                    Always = {}
                
                }
                Octopus.Data.save("RegisteredListener",nil,R_Listner)
            end
            
        end,
        --- 注册并启用一个监听器。
        --- 监听器会在监听到指定事件时，运行记录的脚本。
        ---@param Aargs table 一个由 `Octopus.Listener.new` 创建的监听器配置表。
        open = function (Aargs)---@param Aargs listener listner:{type = ,scriptname = scriptname,id = id}
            Octopus.Listener.__init()
            local type = Aargs["type"]
            local id = Aargs["id"]
            setVar(args,"c",type,"TRUE")
            local R_Listner = Octopus.Data.get_folder("RegisteredListener")
            R_Listner[type][id] = {}
            R_Listner[type][id]["scriptname"] = Aargs["scriptname"] 
            R_Listner[type][id]["scriptargs"] = Aargs["scriptargs"]
            Octopus.Data.save("RegisteredListener",nil,R_Listner)
        end,
        --- 注销并禁用一个监听器。
        ---@param Aargs table 一个由 `Octopus.Listener.new` 创建的监听器配置表。
        close = function (Aargs) ---@param Aargs class listner:{type = ...,scriptname = ...,id = ...}
            local R_Listner_type = Octopus.Data.get_value("RegisteredListener",Aargs["type"])
            R_Listner_type["id"] = nil
            if Octopus.logic.length(R_Listner_type) == 0 then
                setVar(args,"c",Aargs["type"],"FALSE")
            end
                Octopus.Data.save("RegisteredListener",Aargs["type"],R_Listner_type)
        end,

        --- 创建一个新的监听器配置表。
        ---@param type string 监听器类型。必须是 `Octopus.Listener.types` 中定义的一种。
        ---@param scriptname string 触发时要执行的脚本名称。
        ---@param scriptargs any 传递给脚本的参数。
        ---@param id string 监听器的唯一ID。
        ---@return table 一个新的监听器配置表。
        new = function (type,scriptname,scriptargs,id) 
            if 
                Octopus.logic.conclude(Octopus.Listener.types,type)
            then
                return {type = type,scriptname = scriptname,scriptargs = scriptargs,id = id}
            else
                error("ERROR:Invaild Listener Type")
            end
        end
        
        
        
    },
    ---@class Octopus.Operands
    ---@description 用于获取游戏内各种动态信息（操作数）的功能。
    Operands = {
        --- 刷新操作数数据。
        refresh = function ()
            effect("run_workflow",args,"c","refresh_operands")

        end,
        --- 获取玩家名称。
        ---@return string 玩家名称。
        PlayerName = function ()
            return  getVar(args,"c","Octopus_PlayerName")
        end,
        --- 获取当前目标名称。
        ---@return string 目标名称。
        TargetName = function ()
            Octopus.Operands.refresh()
            return getVar(args,"c","Octopus_TargetName")
            
        end
    },
    
    --- 运行指定名称的脚本。
    ---@param scriptname string 要运行的脚本的名称。
    ---@param scripts table 包含脚本函数的表。
    RunScript = function (scriptname,scripts)  --运行指定脚本

        for i,v in pairs(scripts) do
    
            if type(v) == "table" then
                Octopus.RunScript(scriptname,v)
    
            else
                if i == scriptname then
                    scripts[scriptname]()
                end
            end
    
        end
    
    end,
    ---@class Octopus.BasicScripts
    ---@description 提供一些基础的、可被事件或链接调用的脚本。
    BasicScripts = {
        --- 处理菜单关闭逻辑的脚本。
        menuclose = function ()

            if Octopus.GUI.Menu.Config.Confirming() == "TRUE" then
                Octopus.Sound.playSoundSelf(Octopus.Assests.SoundLibrary.UI.CANCEL)
                
                effect("text",args,"已取消！","4")

                Octopus.GUI.Menu.Config.Confirming("FALSE")

                Octopus.GUI.Menu.openlatest()
            end

            

            if Octopus.GUI.Menu.Config.CloseAble() ~= "FALSE" then


                Octopus.GUI.Menu.setlatest(getVar(args,"c","MenuText"))

                Octopus.GUI.Menu.Config.MenuItem_UseAble("TRUE")
                
            
            else
                
                Octopus.GUI.Menu.show()

                Octopus.Sound.playSoundSelf(Octopus.Assests.SoundLibrary.UI.CANCEL)
                
                effect("text",args,"此页面不能被关闭！","4")

            end
        end,
        ---@class Octopus.BasicScripts.ListnerRelatives
        ---@description 与监听器相关的脚本。
        ListnerRelatives = {
            --- 监听器事件的分发脚本，由底层事件触发。
            ListenerHeard = function ()
            
                local listners = Octopus.Data.get_folder("RegisteredListener")
                local atype = getVar(args,"c","ListenerScriptArgs")
                if listners[atype] then
                    for i,v in pairs(listners[atype]) do
                        ScriptArgs = v["scriptargs"]
                        Octopus.RunScript(v["scriptname"],SCRIPTS)
                    end
                end
            end
        },

        --- 一个用于清理/重置临时脚本变量的脚本。
        windup = function ()
            setVar(args,"c","ScriptName","nil")
            setVar(args,"c","ScriptArgs","nil")
            setVar(args,"c","ScriptFilter","nil")
            setVar(args,"c","ListenerScriptName",nil)
        end

    }

    
    
}