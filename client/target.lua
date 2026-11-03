-- Optional ox_target integration: third-eye options instead of E prompts.
local cfg = Config.Target or {}
UseTarget = cfg.enabled ~= false and Utils.IsRunning('ox_target')
if not UseTarget then return end

local T = Utils.T
local zones = {}

local function clearZones()
    for _, id in ipairs(zones) do pcall(function() exports.ox_target:removeZone(id) end) end
    zones = {}
end

local function addZone(coords, radius, options)
    local id = exports.ox_target:addSphereZone({ coords = coords, radius = radius, debug = false, options = options })
    zones[#zones + 1] = id
end

--- Rebuilds catalogue / depot zones (called after every dealership sync)
function RefreshTargets()
    clearZones()
    for _, d in ipairs(State.dealerships) do
        if d.shop then
            local id = d.id
            addZone(ToVec3(d.shop) + vector3(0.0, 0.0, 1.0), 1.4, {
                {
                    name = 'gen_dealership_browse_' .. id, icon = 'fa-solid fa-car', label = ('Browse %s'):format(d.label),
                    canInteract = function() return not UIBusy() and CanAccessDealership(FindDealership(id) or d) end,
                    onSelect = function() local dd = FindDealership(id) if dd then OpenShopFor(dd) end end,
                },
                {
                    name = 'gen_dealership_manage_' .. id, icon = 'fa-solid fa-briefcase', label = 'Manage business',
                    canInteract = function() return not UIBusy() and State.roles[tostring(id)] ~= nil end,
                    onSelect = function() OpenManagement(id) end,
                },
            })
        end
    end
    if Config.Logistics.enabled then
        local b = Config.Logistics.depot.board
        addZone(vector3(b.x, b.y, b.z + 0.5), 1.4, {
            {
                name = 'gen_dealership_logistics', icon = 'fa-solid fa-truck', label = 'Logistics board',
                canInteract = function() return not UIBusy() end,
                onSelect = function() OpenLogisticsBoard() end,
            },
        })
    end
end

--- Showroom display cars
function AddDisplayTarget(entity, d, vehicleId, label)
    exports.ox_target:addLocalEntity(entity, {
        {
            name = 'gen_dealership_td', icon = 'fa-solid fa-key', label = ('Test drive %s'):format(label),
            canInteract = function() return Config.TestDrive.enabled and not UIBusy() end,
            onSelect = function()
                local ok, err = StartTestDriveFor(FindDealership(d.id) or d, vehicleId)
                if not ok and err then Bridge.Notify(err, 'error') end
            end,
        },
        {
            name = 'gen_dealership_view', icon = 'fa-solid fa-tags', label = 'View in catalogue',
            canInteract = function() return not UIBusy() end,
            onSelect = function() local dd = FindDealership(d.id) if dd then OpenShopFor(dd) end end,
        },
    })
end

function RemoveEntityTarget(entity)
    pcall(function() exports.ox_target:removeLocalEntity(entity) end)
end

--- AI customers
function AddCustomerTarget(ped, customerId, dealershipId)
    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'gen_dealership_customer', icon = 'fa-solid fa-comments-dollar', label = 'Talk to customer',
            canInteract = function() return not UIBusy() and State.roles[tostring(dealershipId)] ~= nil end,
            onSelect = function() EngageCustomer(customerId) end,
        },
    })
end

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    Wait(2000)
    RefreshTargets()
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearZones() end
end)
