local json = require("json")

collateralTokenId = "-QOtT3QjypIA8pNoi2Gq958kV8wpedzuektLxQZr_3o"
stablecoinTokenId = "n2rIeHCoaPvFXBsYHmkhBMl5fJF0w99noHz9O17Lnns"
wArPrice = 0
vaults = {} -- { collateral: number, debt: number, collateralRatio: number }

Handlers.add(
    "getCollateralPrice",
    "GetCollateralPrice",
    function(msg)
        local tickers = { "wAR" } -- Replace with your desired tickers
        local response = ao.send({
            Target = "R5rRjBFS90qIGaohtzd1IoyPwZD0qJZ25QXkP7_p5a0",
            Action = "v2.Request-Latest-Data",
            Tags = {
                Tickers = json.encode(tickers)
            }
        }).receive().Data

        local value = json.decode(response)
        wArPrice = value.wAR.v

        msg.reply({
          Data = json.encode(wArPrice)
        })
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

-- Handlers.add("withdrawCollateral", "WithdrawCollateral", function(msg)
--   if not msg.Quantity then
--     msg.reply({
--         Error = "Invalid input. Required: Quantity"
--     })
--     return
--   end

--   local user = Msg.Sender

--   if not vaults.user then
--     msg.reply({
--         Error = "User has no vault"
--     })
--     return
--   end

--   if not vaults.user.collateral then
--     msg.reply({
--         Error = "User has no collateral"
--     })
--     return
--   end

--   local amount = tonumber(msg.Quantity)
--   local collateral = vaults.user.collateral

--   if (not amount or amount <= 0) and amount >= collateral then
--       msg.reply({
--           Error = "Amount must be a positive number and smaller than deposited collateral"
--       })
--       return
--   end

--   local transferResponse = ao.send({
--     Target = collateralTokenId,
--     Action = "Transfer",
--     From = ao.id,
--     To = msg.Sender,
--     Quantity = tostring(amount)
--   }).receive()

--   if not transferResponse or transferResponse.Error then
--     msg.reply({
--         Error = "Failed to transfer collateral: " .. (transferResponse and transferResponse.Error or "Unknown error")
--     })
--     return
--   end

--   -- Update vault state
--   vaults[msg.Sender].debt = vaults[msg.Sender].debt + amount
--   vaults[msg.Sender].collateralRatio = (vaults[msg.Sender].collateral * wArPrice) / vaults[msg.Sender].debt

--   -- Send confirmation
--   msg.reply({
--     Data = {
--         message = "Collateral deposited successfully",
--         vault = vaults[msg.Sender]
--     }
--   })

-- end)
