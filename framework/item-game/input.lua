return function(E, G)
    local pcall = G.pcall
    function E.newInput(session)
        local host, frame = session.host, session.view.frame
        local self = { mode = "observe", down = {}, previous = {}, pressed = {}, blocked = {}, actionPress = {}, eventEdges={} }
        local controls = session.content.controls or { left = {"A", "LEFT"}, right = {"D", "RIGHT"}, jump = {"SPACE"}, attack = {"J"}, fire = {"K"} }
        local keyActions = {}
        for action, keys in pairs(controls) do
            for _, key in ipairs(keys) do keyActions[key] = keyActions[key] or {}; keyActions[key][#keyActions[key] + 1] = action end
        end
        function self.release()
            self.mode = "observe"; self.down = {}; self.previous = {}; self.pressed = {}; self.actionPress = {}; self.blocked = {};self.eventEdges={}
            if frame.SetPropagateKeyboardInput then pcall(frame.SetPropagateKeyboardInput, frame, true) end
            if frame.EnableKeyboard then pcall(frame.EnableKeyboard, frame, false) end
        end
        function self.acquire()
            if not host.environment().allowed or host.textFocused() then return false, "input_context_blocked" end
            if not frame.EnableKeyboard or not frame.SetPropagateKeyboardInput then return false, "keyboard_capture_unavailable" end
            self.release()
            local ok, err = pcall(frame.EnableKeyboard, frame, true)
            if not ok then return false, tostring(err) end
            ok, err = pcall(frame.SetPropagateKeyboardInput, frame, true)
            if not ok then self.release(); return false, tostring(err) end
            self.mode = "capture"
            for key in pairs(keyActions) do self.blocked[key] = host.keyDown(key) == true end
            return true
        end
        local function handle(key, down)
            if session.stopping then return end
            if key == "ESCAPE" and down and self.mode == "capture" then
                session.requestClose("escape")
                -- Closing or pausing releases capture; consume the handled Escape.
                pcall(frame.SetPropagateKeyboardInput, frame, false); return
            end
            if self.mode == "capture" then pcall(frame.SetPropagateKeyboardInput, frame, keyActions[key] == nil or host.textFocused()) end
            if not keyActions[key] or host.textFocused() then return end
            local was=self.down[key]
            self.down[key] = down
            if down and not was and not self.blocked[key] then
                for _,action in ipairs(keyActions[key])do self.actionPress[action]=true end
                self.eventEdges[key]=true;session.perf.increment("inputEdges")
            end
            if not down then self.blocked[key] = nil end
        end
        frame:SetScript("OnKeyDown", function(_, key) handle(key, true) end)
        frame:SetScript("OnKeyUp", function(_, key) handle(key, false) end)
        function self.poll()
            if host.textFocused() then self.release(); return end
            if session.paused then return end
            for key, actions in pairs(keyActions) do
                local value = host.keyDown(key)
                if value ~= nil then self.down[key] = value end
                if self.down[key] == false then self.blocked[key] = nil end
                local active = self.down[key] == true and not self.blocked[key]
                if active and not self.previous[key] and not self.eventEdges[key] then
                    for _, action in ipairs(actions) do self.actionPress[action] = true end
                    session.perf.increment("inputEdges")
                end
                self.previous[key] = active
            end
            self.eventEdges={}
        end
        function self.snapshot()
            local held = {}
            for action, keys in pairs(controls) do
                held[action] = false
                for _, key in ipairs(keys) do if self.down[key] and not self.blocked[key] then held[action] = true end end
            end
            local out = {
                moveX = (held.right and 1 or 0) - (held.left and 1 or 0),
                jumpPressed = self.actionPress.jump == true, attackPressed = self.actionPress.attack == true,
                firePressed = self.actionPress.fire == true, attackHeld = held.attack == true,
                held = held, pressed = E.util.copy(self.actionPress),
            }
            self.actionPress = {}; return out
        end
        function self.emitAction(action, phase)
            if controls[action] == nil then return false, "unknown_action" end
            if phase == "pressed" then self.actionPress[action] = true; return true end
            return false, "only_engine_action_edges_supported"
        end
        function self.readKey(key) return host.keyDown(key) end
        self.release()
        return self
    end
end
