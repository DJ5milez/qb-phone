local QBCore = exports['qb-core']:GetCoreObject()
local CachedJobs = {}
local CachedPlayers = {}

local createPhoneExport = require 'shared.export-function'

local function getJobs(cid)
    local jobs = {}
    local employees = {}
    for k, v in pairs(CachedJobs) do
        if v and v.employees and v.employees[cid] then
            if not jobs[k] then
                jobs[k] = v.employees[cid]
            end

            if not employees[k] then
                employees[k] = v.employees
            end
        end
    end

    return jobs, employees
end createPhoneExport('getJobs', getJobs)

local FirstStart = false

CreateThread(function()
    ---- Convertion Tool I guess LOL ----
    if not FirstStart then return end
    while not QBCore do Wait(25) end
    for k, _ in pairs(exports.qbx_core:GetJobs()) do
        if k ~= 'unemployed' then
            if not CachedJobs[k] then CachedJobs[k] = {} end

            local jobCheck = MySQL.query.await('SELECT * FROM player_jobs WHERE jobname = ?', { k })
            local players = MySQL.query.await("SELECT * FROM `players` WHERE `job` LIKE '%".. k .."%'", {})

            if players[1] then
                for _, v in pairs(players) do
                    --if v.job == ignoredJobs then return end
                    if not v.job then return end

                    local grade = json.decode(v.job).grade.level or false
                    local FirstName = json.decode(v.charinfo) and json.decode(v.charinfo).firstname or false
                    local LastName = json.decode(v.charinfo) and json.decode(v.charinfo).lastname or false

                    if grade and exports.qbx_core:GetJobs()[k].grades and exports.qbx_core:GetJobs()[k].grades[grade] and v.citizenid and v.charinfo and FirstName and LastName then
                        if not CachedJobs[k].employees then CachedJobs[k].employees = {} end
                        if not CachedJobs[k].employees[v.citizenid] then

                            CachedJobs[k].employees[v.citizenid] = {
                                cid = v.citizenid,
                                grade = json.decode(v.job).grade.level,
                                name = json.decode(v.charinfo).firstname .. ' ' .. json.decode(v.charinfo).lastname
                            }
                        end
                    end
                end

                if not jobCheck[1] then -- Create job w/ employees if non-existent
                    MySQL.insert('INSERT INTO player_jobs (`jobname`, `employees`) VALUES (?, ?)', {
                        k,
                        json.encode(CachedJobs[k].employees)
                    })
                else -- Update employees if job exist
                    MySQL.update('UPDATE player_jobs SET employees = ? WHERE jobname = ?', {
                        json.encode(CachedJobs[k].employees),
                        k
                    })
                end
            else
                if not jobCheck[1] then -- Create job w/o employees if it does not exist
                    MySQL.insert('INSERT INTO player_jobs (`jobname`, `employees`) VALUES (?, ?)', {
                        k,
                        json.encode({})
                    })
                end
            end
            Wait(10)
        end
    end
end)

CreateThread(function()
    if FirstStart then return end
    while not QBCore do Wait(25) end

    local jobs = MySQL.query.await("SELECT * FROM `player_jobs`", {})
    if jobs[1] then
        for _, v in pairs(jobs) do
            if not CachedJobs[v.jobname] then
                CachedJobs[v.jobname] = {
                    employees = json.decode(v.employees),
                    maxEmployee = v.maxEmployee
                }
            end
        end
    end
end)

local function notifyPlayer(src, message)
    if not src or not message then return end

    TriggerClientEvent('qb-phone:client:CustomNotification', src,
        "Employment",
        message,
        "fas fa-network-wired",
        "#FFFC00",
        10000
    )
end

local function JobsHandler(source, Job, CID, grade)
    local src = source
    local srcPlayer = exports.qbx_core:GetPlayer(src)

    if not srcPlayer then return print("no source") end

    local srcCID = srcPlayer.PlayerData.citizenid

    if not Job or not CID or not CachedJobs[Job] then return end
    local Player = exports.qbx_core:GetPlayerByCitizenId(CID)
    if not CachedJobs[Job].employees[CID] then return notifyPlayer(src, "Citizen is not employed at the job...") end
    if grade > CachedJobs[Job].employees[srcCID].grade then return notifyPlayer(src, "You cannot promote someone higher than you...") end

    CachedJobs[Job].employees[CID].grade = grade

    MySQL.update('UPDATE player_jobs SET employees = ? WHERE jobname = ?', { json.encode(CachedJobs[Job].employees), Job })

    TriggerClientEvent("qb-phone:client:JobsHandler", -1, Job, CachedJobs[Job].employees)

    if Player and CachedPlayers[CID] then
        CachedPlayers[CID][Job] = CachedJobs[Job].employees[CID]

        local newGrade = type(CachedJobs[Job].employees[CID].grade) ~= "number" and tonumber(CachedJobs[Job].employees[CID].grade) or CachedJobs[Job].employees[CID].grade
        Player.Functions.SetJob(Job, newGrade)

        TriggerClientEvent('qb-phone:client:MyJobsHandler', Player.PlayerData.source, Job, CachedPlayers[CID][Job], CachedJobs[Job].employees)
    end
end
createPhoneExport('JobsHandler', JobsHandler)

-- ** Fire someone in the business the player firing someone MUST be boss ** --
RegisterNetEvent('qb-phone:server:fireUser', function(Job, sCID)
    local src = source
    local srcPlayer = QBCore.Functions.GetPlayer(src)
    local CID = tostring(sCID) -- For some reason my CIDs are returning as a number and not a string so hotfix incase urs do the same

    if not Job or not CID then return end
    if not CachedJobs[Job] then return end
    if not CachedJobs[Job].employees[CID] then return notifyPlayer(src, "Citizen is not Employed...") end
    if not srcPlayer then return notifyPlayer(src, "Citizen not found.") end

    local srcCID = srcPlayer.PlayerData.citizenid

    if srcCID == CID then return end

    if not CachedJobs[Job].employees[srcCID].grade then return end

    local grade = CachedJobs[Job].employees[srcCID].grade
    if not exports.qbx_core:GetJobs()[Job].grades[grade].isboss then return end

    if CachedJobs[Job].employees[srcCID].grade < CachedJobs[Job].employees[CID].grade then return end


    CachedJobs[Job].employees[CID] = nil
    MySQL.update('UPDATE player_jobs SET employees = ? WHERE jobname = ?',{json.encode(CachedJobs[Job].employees), Job})

    TriggerClientEvent("qb-phone:client:JobsHandler", -1, Job, CachedJobs[Job].employees)

    notifyPlayer(src, "Successfully fired Employee...")

    if not CachedPlayers[CID] then return end
    if not CachedPlayers[CID][Job] then return end
    CachedPlayers[CID][Job] = nil

    local Player = QBCore.Functions.GetPlayerByCitizenId(CID)
    if not Player then return end

    if Player.PlayerData.job.name == Job then
        Player.Functions.SetJob("unemployed", 0)
    end

    if Player.PlayerData.source then
        TriggerClientEvent('qb-phone:client:MyJobsHandler', Player.PlayerData.source, Job, nil, nil)
    end
end)

---- ** Can give any employee x amount of money out of the bank account, must be boss ** ----
RegisterNetEvent('qb-phone:server:SendEmploymentPayment', function(Job, CID, amount)
    local src = source
    if not Job or not CID or not amount or not CachedJobs[Job] or Job == "unemployed" then return end
    local Player = QBCore.Functions.GetPlayer(src)

    if not Player then return end

    local srcCID = Player.PlayerData.citizenid

    --if srcCID == CID then return end

    if not CachedJobs[Job].employees[srcCID].grade then return end

    local grade = CachedJobs[Job].employees[srcCID].grade
    if not exports.qbx_core:GetJobs()[Job].grades[grade].isboss then return notifyPlayer(src, "You aren't a manager...") end

    local Reciever = QBCore.Functions.GetPlayerByCitizenId(CID)
    if not Reciever then return notifyPlayer(src, "Employee not found...") end

    local amt = tonumber(amount)
    if Config.RenewedBanking then
        if not exports['Renewed-Banking']:removeAccountMoney(Job, amt) then return notifyPlayer(src, "Insufficient Funds...") end
        local title = exports.qbx_core:GetJobs()[Job].label.." // Employee Payment"

        ---- Business Account ----
        local BusinessName = ("%s %s"):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname)
        local RecieverName = ("%s %s"):format(Reciever.PlayerData.charinfo.firstname, Reciever.PlayerData.charinfo.lastname)
        local trans = exports['Renewed-Banking']:handleTransaction(Job, title, amt, "Payment given of $"..amt.." given to "..RecieverName, BusinessName, RecieverName, "withdraw")

        ---- Player Account ----
        exports['Renewed-Banking']:handleTransaction(Reciever.PlayerData.citizenid, title, amt, "Payment recieved of $"..amt.." recieved from Business "..exports.qbx_core:GetJobs()[Job].label.. " and Manager "..BusinessName, BusinessName, RecieverName, "deposit", trans.trans_id)
    else
        if not exports['qb-management']:RemoveMoney(Job, amt) then return notifyPlayer(src, "Insufficient Funds...") end
    end
    Player.Functions.AddMoney('bank', amt, 'Employment Payment')
end)

---- ** Player can hire someone aslong as they are boss within the group
RegisterNetEvent('qb-phone:server:hireUser', function(Job, id, grade)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local hiredPlayer = QBCore.Functions.GetPlayer(tonumber(id))

    local pCID = Player.PlayerData.citizenid
    local CID = hiredPlayer.PlayerData.citizenid
    if not hiredPlayer then return notifyPlayer(src, "Citizen not found...") end
    if not Job or not CID or not CachedJobs[Job] or Job == "unemployed" then return end

    if CachedJobs[Job].employees[CID] then return notifyPlayer(src, "Citizen Already Hired...") end

    if not CachedJobs[Job].employees[pCID] or not CachedJobs[Job].employees[pCID].grade then return end

    local bossGrade = CachedJobs[Job].employees[pCID].grade
    if not exports.qbx_core:GetJobs()[Job].grades[bossGrade].isboss then return notifyPlayer(src, "You arent a manager // boss...") end

    CachedJobs[Job].employees[CID] = {
        cid = CID,
        grade = tonumber(grade) or 0,
        name = hiredPlayer.PlayerData.charinfo.firstname .. ' ' .. hiredPlayer.PlayerData.charinfo.lastname
    }

    MySQL.update('UPDATE player_jobs SET employees = ? WHERE jobname = ?',{json.encode(CachedJobs[Job].employees), Job})

    TriggerClientEvent("qb-phone:client:JobsHandler", -1, Job, CachedJobs[Job].employees)

    if hiredPlayer and CachedPlayers[CID] then
        CachedPlayers[CID][Job] = CachedJobs[Job].employees[CID]
        TriggerClientEvent('qb-phone:client:MyJobsHandler', hiredPlayer.PlayerData.source, Job, CachedPlayers[CID][Job], CachedJobs[Job].employees)
    end
end)

---- ** Handles the changing of someone grade within the job ** ----

RegisterNetEvent('qb-phone:server:gradesHandler', function(Job, CID, grade)
    local src = source
    local srcPlayer = QBCore.Functions.GetPlayer(src)

    if not srcPlayer then return print("no source") end

    local srcCID = srcPlayer.PlayerData.citizenid

    if not Job or not CID or not CachedJobs[Job] then return end
    local Player = QBCore.Functions.GetPlayerByCitizenId(CID)
    if not CachedJobs[Job].employees[CID] then return notifyPlayer(src, "Citizen is not employed at the job...") end

    if not CachedJobs[Job].employees[srcCID] then return  end

    if tonumber(grade) > tonumber(CachedJobs[Job].employees[srcCID].grade) then return notifyPlayer(src, "You cannot promote someone higher than you...") end

    local bossGrade = CachedJobs[Job].employees[srcCID].grade
    if not exports.qbx_core:GetJobs()[Job].grades[bossGrade].isboss then return notifyPlayer(src, "You arent a manager // boss...") end

    CachedJobs[Job].employees[CID].grade = tonumber(grade)

    MySQL.update('UPDATE player_jobs SET employees = ? WHERE jobname = ?',{json.encode(CachedJobs[Job].employees), Job})

    TriggerClientEvent("qb-phone:client:JobsHandler", -1, Job, CachedJobs[Job].employees)

    if Player and CachedPlayers[CID] then
        CachedPlayers[CID][Job] = CachedJobs[Job].employees[CID]

        local newGrade = type(CachedJobs[Job].employees[CID].grade) ~= "number" and tonumber(CachedJobs[Job].employees[CID].grade) or CachedJobs[Job].employees[CID].grade
        Player.Functions.SetJob(Job, newGrade)

        TriggerClientEvent('qb-phone:client:MyJobsHandler', Player.PlayerData.source, Job, CachedPlayers[CID][Job], CachedJobs[Job].employees)
    end
end)


RegisterNetEvent('qb-phone:server:clockOnDuty', function(Job)
    local src = source
    if not Job then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local CID = Player.PlayerData.citizenid

    if CachedPlayers[CID][Job] and CachedJobs[Job].employees[CID] then
        local grade = type(CachedJobs[Job].employees[CID].grade) ~= "number" and tonumber(CachedJobs[Job].employees[CID].grade) or CachedJobs[Job].employees[CID].grade
        Player.Functions.SetJob(Job, grade)
        Wait(50)
        if Player.PlayerData.job.onduty then
            notifyPlayer(src, "You have signed off duty")
            Player.Functions.SetJobDuty(true)
        else
            notifyPlayer(src, "You have signed on duty")
            Player.Functions.SetJobDuty(false)
        end
        TriggerClientEvent('qb-phone:client:clearAppAlerts', src)
    end
end)

---- Gets the client side cache for players ----
lib.callback.register("qb-phone:server:GetMyJobs", function(source)
    if FirstStart then return nil, nil end  -- Return explicit nil if FirstStart is true
    local Player = exports.qbx_core:GetPlayer(source)

    if not Player then return nil, nil end  -- Return explicit nil if Player is not found

    local job = Player.PlayerData.job.name
    local CID = Player.PlayerData.citizenid
    local employees
    CachedPlayers[CID], employees = getJobs(CID)

    -- Initialize employees as an empty table if getJobs returns nil
    if not employees then employees = {} end
    if not CachedPlayers[CID] then CachedPlayers[CID] = {} end

    -- If you were fired while being offline it will remove the job
    if not CachedPlayers[CID][job] then
        Player.Functions.SetJob("unemployed", 0)
    end

    return employees, CachedPlayers[CID]
end)


---- Functions and Exports people can use across script to hire and fire people to sync ----

---- Use this to hire anyone through scripts DO NOT use this through exploitable events since its meant to not be the securest ----
local function hireUser(Job, CID, grade)
    if not Job or not CID or not CachedJobs[Job] or Job == "unemployed" then return end
    local Player = QBCore.Functions.GetPlayerByCitizenId(CID)

    if not Player then return print("Player offline") end

    if CachedJobs[Job].employees[CID] then return print("Already hired") end

    CachedJobs[Job].employees[CID] = {
        cid = CID,
        grade = grade or 0,
        name = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    }

    MySQL.update('UPDATE player_jobs SET employees = ? WHERE jobname = ?',{json.encode(CachedJobs[Job].employees), Job})

    if CachedPlayers[CID] then
        CachedPlayers[CID][Job] = CachedJobs[Job].employees[CID]
        TriggerClientEvent('qb-phone:client:MyJobsHandler', Player.PlayerData.source, Job, CachedPlayers[CID][Job], CachedJobs[Job].employees)
    end

    TriggerClientEvent("qb-phone:client:JobsHandler", -1, Job, CachedJobs[Job].employees)
end createPhoneExport("hireUser", hireUser)

---- Use this to fire anyone through scripts DO NOT use this through exploitable events since its meant to not be the securest ----
local function fireUser(Job, CID)
    if not CachedJobs[Job] then return print("Not Cached job") end
    if not CachedJobs[Job].employees[CID] then return print("Player is not employed LOL") end

    CachedJobs[Job].employees[CID] = nil
    MySQL.update('UPDATE player_jobs SET employees = ? WHERE jobname = ?',{json.encode(CachedJobs[Job].employees), Job})

    TriggerClientEvent("qb-phone:client:JobsHandler", -1, Job, CachedJobs[Job].employees)

    if not CachedPlayers[CID] then return end
    if not CachedPlayers[CID][Job] then return end
    CachedPlayers[CID][Job] = nil

    local Player = QBCore.Functions.GetPlayerByCitizenId(CID)
    if not Player then return end

    if Player.PlayerData.job.name == Job then
        Player.Functions.SetJob("unemployed", 0)
    end

    if Player.PlayerData.source then
        TriggerClientEvent('qb-phone:client:MyJobsHandler', Player.PlayerData.source, Job, nil, nil)
    end
end createPhoneExport("fireUser", fireUser)

local bills = {}

---- ** Invoices // Charging People ** ----
RegisterNetEvent('qb-phone:server:ChargeCustomer', function(id, amount, notes, job)
    if not id or not amount or not job then return end
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    if not CachedJobs[job].employees[Player.PlayerData.citizenid] then return notifyPlayer(src, "You're not an employee at this business...") end

    local note = notes or ""
    local amt = tonumber(amount)

    bills[tonumber(id)] = {
        amount = amt,
        job = job,
        notes = note,
        coords = GetEntityCoords(GetPlayerPed(src)),
        name = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    }

    TriggerEvent('qb-phone:server:CreateInvoice', tonumber(id), src, amt)
end)

AddEventHandler('qb-phone:server:InvoiceHandler', function(paid, amount, source, resource)
    if not bills[source] then return end
    if resource ~= GetCurrentResourceName() then return end

    if paid then
        if amount == bills[source].amount then
            local Player = QBCore.Functions.GetPlayer(source)
            if Config.RenewedBanking then
                local cid = Player.PlayerData.citizenid
                local name = ("%s %s"):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname)
                local text = "You paid off an invoice for $"..amount.." from "..bills[source].name.." for "..bills[source].notes
                local trans = exports['Renewed-Banking']:handleTransaction(cid, "Personal // Invoice Transaction", amount, text, bills[source].name, name, "withdraw")

                local text2 = "A invoice issued by "..bills[source].name.." Worth $"..amount.." was paid off by "..name.." for "..bills[source].notes
                exports['Renewed-Banking']:handleTransaction(bills[source].job, "Business // Invoice Transaction", amount, text2, bills[source].name, name, "deposit", trans.trans_id)
                exports['Renewed-Banking']:addAccountMoney(bills[source].job, amount)
            else
                exports['qb-management']:AddMoney(bills[source].job, amount)
            end

            if amount >= 450 then
                local DutySrcs, count = QBCore.Functions.GetPlayersOnDuty(bills[source].job)
                if count > 0 then
                    for i  = 1, count do
                        local ped = GetPlayerPed(DutySrcs[i])
                        local coords = GetEntityCoords(ped)

                        if #(coords - bills[source].coords) < 10.0 then
                            local tempPlayer = QBCore.Functions.GetPlayer(DutySrcs[i])
                            tempPlayer.Functions.AddItem('payticket', 1)
                            TriggerClientEvent('QBCore:Notify', DutySrcs[i], 'Receipt received', 'success')
                        end
                    end
                end
            end

            bills[source] = nil
        end
    elseif not paid then
        bills[source] = nil
    end
end)