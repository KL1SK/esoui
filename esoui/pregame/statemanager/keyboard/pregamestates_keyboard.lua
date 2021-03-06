local pregameStates =
{
    ["CharacterSelect"] =
    {
        OnEnter = function()
            Pregame_ShowScene("gameMenuCharacterSelect")
            if DoesPlatformRequirePregamePEGI() and not HasAgreedToPEGI() then
                ZO_Dialogs_ShowDialog("PEGI_COUNTRY_SELECT")
            end
        end,

        OnExit = function()
            TrySaveCharacterListOrder()
        end
    },

    ["ShowEULA"] =
    {
        ShouldAdvance = function()
            return not ZO_ShouldShowEULAScreen()
        end,

        OnEnter = function()
            SCENE_MANAGER:Show("eula")
        end,

        OnExit = function()
        end,

        GetStateTransitionData = function()
            return "AccountLogin"
        end,
    },

    ["AccountLogin"] =
    {
        OnEnter = function(allowAnimation)
            if DoesPlatformSupportDisablingShareFeatures() then
                -- re-enabled when the character list is loaded
                DisableShareFeatures()
            end
            LOGIN_KEYBOARD:InitializeCredentialEditBoxes()
            PREGAME_SLIDESHOW_KEYBOARD:BeginSlideShow()
            PregameLogout()
            RegisterForLoadingUpdates()

            if(ZO_PREGAME_HAD_GLOBAL_ERROR) then
                AbortVideoPlayback()
            end

            ZO_PREGAME_FIRED_CHARACTER_CONSTRUCTION_READY = false
            ZO_PREGAME_CHARACTER_LIST_RECEIVED = false
            ZO_PREGAME_CHARACTER_COUNT = 0

            Pregame_ShowScene("gameMenuPregame")

            if(ZO_ServerSelectCancel ~= nil) then
                ZO_ServerSelectCancel.gameStateString = "AccountLogin"
            end

            AttemptQuickLaunch()
        end,

        OnExit = function()
        end
    },
    
    ["WorldSelect_Requested"] =
    {
        OnEnter = function()
            ZO_Dialogs_ShowDialog("REQUESTING_WORLD_LIST")
            RequestWorldList()
        end,

        OnExit = function()
        end
    },

    ["WorldSelect_ShowList"] =
    {
        OnEnter = function()
            ZO_ServerSelect_SetSelectionEnabled(true)
            Pregame_ShowScene("serverSelect")
        end,

        OnExit = function()
        end
    },

    ["ServerSelectIntro"] =
    {
        ShouldAdvance = function()
            return GetCVar("IsServerSelected") == "1"
        end,

        OnEnter = function()
            ZO_Dialogs_ShowDialog("SERVER_SELECT_DIALOG", {isIntro = true})
        end,

        OnExit = function()
        end,

        GetStateTransitionData = function()
            return "ShowEULA"
        end
    },
}

PregameStateManager_AddKeyboardStates(pregameStates)

--[[
Various PC-only functions.
]]--

local function OnServerLocked()
    ZO_Dialogs_ShowDialog("SERVER_LOCKED")
end

local function OnWorldListReceived()
    if(PregameStateManager_GetCurrentState() == "WorldSelect_Requested") then
        PregameStateManager_SetState("WorldSelect_ShowList")
    end
end

local errorCodeToStateChange =
{
    [GLOBAL_ERROR_CODE_LOBBY_WORLD_PERMISSIONS] = "CharacterSelect_FromIngame",
    [GLOBAL_ERROR_CODE_LOBBY_CHARACTER_LOCKED] = "CharacterSelect_FromIngame",
    [GLOBAL_ERROR_CODE_LOBBY_CHARACTER_RENAME_NEEDED] = "CharacterSelect_FromIngame",
    [GLOBAL_ERROR_CODE_LOBBY_TRANSFER_FAILED] = "CharacterSelect_FromIngame",
    [GLOBAL_ERROR_CODE_LOBBY_CHAR_STILL_IN_GAME] = "CharacterSelect_FromIngame",
}

local function GlobalError(eventCode, errorCode, helpLinkURL, ...)
    ZO_PREGAME_HAD_GLOBAL_ERROR = true

    local errorString, errorStringFormat

    if(errorCode ~= nil) then
        errorStringFormat = GetString("SI_GLOBALERRORCODE", errorCode)

        if(errorStringFormat ~= "") then
            if(select("#", ...) > 0) then
                errorString = zo_strformat(errorStringFormat, ...)
            else
                errorString = errorStringFormat
            end
        end
    end

    if(not errorString or errorString == "") then
        errorString = GetString(SI_UNKNOWN_ERROR)
    end

    if(errorCodeToStateChange[errorCode]) then
        PregameStateManager_SetState(errorCodeToStateChange[errorCode])
    else
        PregameStateManager_ReenterLoginState()
    end

    local force = true
    ZO_Dialogs_ReleaseAllDialogs(force)
    if helpLinkURL then
        ZO_Dialogs_ShowDialog("HANDLE_ERROR_WITH_HELP", {url = helpLinkURL}, {mainTextParams = {errorString}})
    else
        ZO_Dialogs_ShowDialog("HANDLE_ERROR", nil, {mainTextParams = {errorString}})
    end
end

local function ServerDisconnectError(eventCode)
    local logoutError, globalErrorCode = GetErrorQueuedFromIngame()

    ZO_PREGAME_HAD_GLOBAL_ERROR = true

    local errorString
    local errorStringFormat

    if logoutError ~= nil and logoutError ~= LOGOUT_ERROR_UNKNOWN_ERROR then
        errorStringFormat = GetString("SI_LOGOUTERROR", logoutError)

        if errorStringFormat ~= ""  then
            errorString = zo_strformat(errorStringFormat, GetGameURL())
        end
    elseif globalErrorCode ~= nil and globalErrorCode ~= GLOBAL_ERROR_CODE_NO_ERROR then
        -- if the error code is not in LogoutReason then it is probably in the GlobalErrorCode enum 
        errorStringFormat = GetString("SI_GLOBALERRORCODE", globalErrorCode)

        if errorStringFormat ~= ""  then
            errorString = zo_strformat(errorStringFormat, globalErrorCode)
        end
    end

    if(not errorString or errorString == "") then
        errorString = GetString(SI_UNKNOWN_ERROR)
    end

    PregameStateManager_ReenterLoginState()

    local force = true
    ZO_Dialogs_ReleaseAllDialogs(force)

    ZO_Dialogs_ShowDialog("HANDLE_ERROR", nil, {mainTextParams = {errorString}})
end

local function OnVideoPlaybackComplete()
    EVENT_MANAGER:UnregisterForEvent("PregameStateManager", EVENT_VIDEO_PLAYBACK_COMPLETE)
    EVENT_MANAGER:UnregisterForEvent("PregameStateManager", EVENT_VIDEO_PLAYBACK_ERROR)

    if not ZO_PREGAME_HAD_GLOBAL_ERROR then
        if IsPlayingChapterOpeningCinematic() then
            ZO_PREGAME_IS_CHAPTER_OPENING_CINEMATIC_PLAYING = false
            AttemptToAdvancePastChapterOpeningCinematic()
        else
            PregameStateManager_AdvanceState()
        end
    end
end

function ZO_PlayVideoAndAdvance(...)
    EVENT_MANAGER:RegisterForEvent("PregameStateManager", EVENT_VIDEO_PLAYBACK_COMPLETE, OnVideoPlaybackComplete)
    EVENT_MANAGER:RegisterForEvent("PregameStateManager", EVENT_VIDEO_PLAYBACK_ERROR, OnVideoPlaybackComplete)
    PlayVideo(...)
end

local LOGIN_REQUEST_TIME_MAX = 60
function PregameStateManager_ShowLoginRequested()
    ZO_Dialogs_ShowDialog("LOGIN_REQUESTED", {loginTimeMax = LOGIN_REQUEST_TIME_MAX})
end

--[[
    Initialization and Event Registration
]]--

local function PregameStateManager_Initialize()
    EVENT_MANAGER:RegisterForEvent("PregameStateManager", EVENT_SERVER_LOCKED,                      OnServerLocked)
    EVENT_MANAGER:RegisterForEvent("PregameStateManager", EVENT_WORLD_LIST_RECEIVED,                OnWorldListReceived)
    EVENT_MANAGER:RegisterForEvent("PregameStateManager", EVENT_DISCONNECTED_FROM_SERVER,           ServerDisconnectError)
    EVENT_MANAGER:RegisterForEvent("PregameStateManager", EVENT_GLOBAL_ERROR,                       GlobalError)

    local function OnPregameUILoaded(eventId, addOnName)
        if(addOnName == "ZO_Pregame") then
            RegisterForLoadingUpdates()
            EVENT_MANAGER:UnregisterForEvent("PregameStateManager", EVENT_ADD_ON_LOADED)
        end
    end

    EVENT_MANAGER:RegisterForEvent("PregameStateManager", EVENT_ADD_ON_LOADED, OnPregameUILoaded)
end

PregameStateManager_Initialize()
