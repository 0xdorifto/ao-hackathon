local json = require("json")

collateralTokenId = "-QOtT3QjypIA8pNoi2Gq958kV8wpedzuektLxQZr_3o"
stablecoinTokenId = "n2rIeHCoaPvFXBsYHmkhBMl5fJF0w99noHz9O17Lnns"
wArPrice = 0
minimumCollateralRatio = 1.1
vaults = {} -- { collateral: number, debt: number, collateralRatio: number }

Handlers.add(
  "CronTick", 
  Handlers.utils.hasMatchingTag("Action", "Cron"),
  function(msg)
    local tickers = { "wAR" }
    local response = ao.send({
        Target = "R5rRjBFS90qIGaohtzd1IoyPwZD0qJZ25QXkP7_p5a0",
        Action = "v2.Request-Latest-Data",
        Tags = {
            Tickers = json.encode(tickers)
        }
    }).receive().Data

    local value = json.decode(response)
    wArPrice = value.wAR.v

    print(wArPrice)
end
)

Handlers.add("depositCollateral", "Credit-Notice", function(msg)
    if msg["X-DepositCollateral"] == "True" then
        -- Initialize or update vault
        if not vaults[msg.Sender] then
            vaults[msg.Sender] = {
                collateral = 0,
                debt = 0,
                collateralRatio = 0
            }
        end

        local amount = tonumber(msg.Quantity)

        -- Update vault state
        vaults[msg.Sender].collateral = vaults[msg.Sender].collateral + amount

        if not vaults[msg.Sender].debt or vaults[msg.Sender].debt == 0 then
            vaults[msg.Sender].collateralRatio = 999
        else 
            vaults[msg.Sender].collateralRatio = (vaults[msg.Sender].collateral * wArPrice) / vaults[msg.Sender].debt
        end

        -- Send confirmation
        msg.reply({
            Data = {
                message = "Collateral deposited successfully",
                vault = vaults[msg.Sender]
            }
        })
    else 
        ao.send({
            Target = msg.Sender,
            Action = "Transfer",
            Quantity = msg.Quantity,
            Recipient = msg.Sender
        })
    end
end)

Handlers.add("withdrawCollateral", "WithdrawCollateral", function(msg)
    if not msg.Quantity then
        msg.reply({
            Error = "Invalid input. Required: Quantity"
        })
        return
    end

    local user = msg.From

    if not vaults[user] then
        msg.reply({
            Error = "User has no vault"
        })
        return
    end

    local amount = tonumber(msg.Quantity)
    local collateral = vaults[user].collateral
    if not amount or amount <= 0 or amount >= collateral then
        msg.reply({
            Error = "Amount must be a positive number and smaller than deposited collateral"
        })
        return
    end

    print("amount is allowed")

    local collateralRatio = (vaults[msg.From].collateral * wArPrice) / (vaults[msg.From].debt + amount)
    if collateralRatio < minimumCollateralRatio then
      msg.reply({
          Error = "Collateral would be below minimum"
      })
      return
    end

    print("collateral is allowed")

    local transferResponse = ao.send({
        Target = collateralTokenId,
        Action = "Transfer",
        From = ao.id,
        Recipient = msg.From,
        Quantity = tostring(amount)
    }).receive()


    if not transferResponse or transferResponse.Error then
        msg.reply({
            Error = "Failed to transfer collateral: " .. (transferResponse and transferResponse.Error or "Unknown error")
        })
        return
    end

    -- Update vault state: subtract from collateral, not add to debt
    vaults[msg.From].collateral = vaults[msg.From].collateral - amount
    
    -- Update collateral ratio with proper zero debt handling
    if not vaults[msg.From].debt or vaults[msg.From].debt == 0 then
        vaults[msg.From].collateralRatio = 999
    else 
        vaults[msg.From].collateralRatio = collateralRatio
    end

    -- Send confirmation with correct message
    msg.reply({
        Data = {
            message = "Collateral withdrawn successfully",
            vault = vaults[msg.From]
        }
    })
end)
