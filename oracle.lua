local json = require("json")

collateralTokenId = "LDpoTGBAoelDA9kMbV28J5fb32hIqH16mRv3KlAFL0U"
stablecoinTokenId = "FYGz2V2RW-4hRI4EozeUMBzHH47JqOLXGz5CtBwwLu0"
wArPrice = wArPrice or 0
minimumCollateralRatio = 1.1
vaults = vaults or {} -- { collateral: number, debt: number, collateralRatio: number }
stabilityPool = stabilityPool or {} -- { deposit: number}
totalCollateral = totalCollateral or 0
totalDebt = totalDebt or 0
totalStabilityPool = totalStabilityPool or 0

Handlers.add(
  "CronTick", 
  Handlers.utils.hasMatchingTag("Action", "Cron"),
  function()
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

      totalCollateral = totalCollateral + amount

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

    local collateralRatio = ((vaults[msg.From].collateral - amount) * wArPrice) / (vaults[msg.From].debt)
    if collateralRatio < minimumCollateralRatio then
      msg.reply({
          Error = "Collateral would be below minimum"
      })
      return
    end

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

    totalCollateral = totalCollateral - amount

    -- Send confirmation with correct message
    msg.reply({
        Data = {
            message = "Collateral withdrawn successfully",
            vault = vaults[msg.From]
        }
    })
end)

Handlers.add("mintStablecoin", "MintStablecoin", function(msg)
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
  if not amount or amount <= 0 then
      msg.reply({
          Error = "Amount must be a positive number"
      })
      return
  end

  local collateralRatio = (vaults[msg.From].collateral * wArPrice) / (vaults[msg.From].debt + amount)
  if collateralRatio < minimumCollateralRatio then
    msg.reply({
        Error = "Collateral would be below minimum"
    })
    return
  end

  local mintResponse = ao.send({
    Target = stablecoinTokenId,
    Action = "Mint",
    From = ao.id,
    Recipient = msg.From,
    Quantity = tostring(amount)
  }).receive()

  if not mintResponse or mintResponse.Error then
    msg.reply({
        Error = "Failed to mint stablecoin: " .. (mintResponse and mintResponse.Error or "Unknown error")
    })
    return
  end

  vaults[msg.From].debt = vaults[msg.From].debt + amount
  vaults[msg.From].collateralRatio = collateralRatio

  totalDebt = totalDebt + amount

  msg.reply({
    Data = {
        message = "Stablecoin minted successfully",
        vault = vaults[msg.From]
    }
  })
end)

Handlers.add("repayStablecoin", "Burn-Notice", function(msg)
    if msg["X-RepayStablecoin"] == "True" then
      print("Detecting burn")
      local amount = tonumber(msg.Quantity)
  
      vaults[msg.From].debt = vaults[msg.From].debt - amount
      vaults[msg.From].collateralRatio = vaults[msg.From].collateral / vaults[msg.From].debt

      totalDebt = totalDebt - amount
  
      msg.reply({
        Data = {
          message = "Stablecoin repayed successfully",
          vault = vaults[msg.From]
        }
      })
    else
      ao.send({
          Target = msg.From,
          Action = "Transfer",
          Quantity = msg.Quantity,
          Recipient = msg.Sender
      })
    end
  end)


  Handlers.add("depositStablecoin", "Credit-Notice", function(msg)
    if msg["X-DepositStablecoin"] == "True" then
        -- Initialize or update vault
        if not stabilityPool[msg.Sender] then
            vaults[msg.Sender] = {
                deposit = 0,
            }
        end
    
        local amount = tonumber(msg.Quantity)
        stabilityPool[msg.Sender] = stabilityPool[msg.Sender] + amount

        totalStabilityPool = totalStabilityPool + amount

        msg.reply({
            Data = {
                message = "Stablecoin deposited successfully",
                stabilityPool = stabilityPool[msg.Sender]
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

  Handlers.add("withdrawStablecoin", "WithdrawStablecoin", function(msg)
    if not msg.Quantity then
        msg.reply({
            Error = "Invalid input. Required: Quantity"
        })
        return
    end

    local user = msg.From

    if not stabilityPool[user] then
        msg.reply({
            Error = "User has no stabilityPool"
        })
        return
    end

    local amount = tonumber(msg.Quantity)
    if not amount or amount <= 0 or amount >= vaults[user] then
        msg.reply({
            Error = "Amount must be a positive number and smaller than deposited stablecoin"
        })
        return
    end

    local transferResponse = ao.send({
        Target = stablecoinTokenId,
        Action = "Transfer",
        From = ao.id,
        Recipient = msg.From,
        Quantity = tostring(amount)
    }).receive()

    if not transferResponse or transferResponse.Error then
        msg.reply({
            Error = "Failed to transfer stablecoin: " .. (transferResponse and transferResponse.Error or "Unknown error")
        })
        return
    end

    stabilityPool[msg.Sender] = stabilityPool[msg.Sender] - amount
    totalStabilityPool = totalStabilityPool - amount

    -- Send confirmation with correct message
    msg.reply({
        Data = {
            message = "Stablecoin withdrawn successfully",
            vault = vaults[msg.From]
        }
    })
end)

-- Getters

Handlers.add("getMinimumCollateralRatio", "GetMinimumCollateralRatio", function(msg)
    msg.reply({
        Data = {
            minimumCollateralRatio = minimumCollateralRatio
        }
    })
end)

Handlers.add("getCollateralPrice", "GetCollateralPrice", function(msg)
    msg.reply({
        Data = {
            collateralPrice = wArPrice
        }
    })
end)

Handlers.add("getVaults", "GetVaults", function(msg)
    msg.reply({
        Data = {
            vaults = vaults
        }
    })
end)

Handlers.add("getUserVault", "GetUserVault", function(msg)
    if not msg.From then
        msg.reply({
            Error = "User address is required"
        })
        return
    end

    local userVault = vaults[msg.From]
    if not userVault then
        msg.reply({
            Data = {
                vault = {
                    collateral = 0,
                    debt = 0,
                    collateralRatio = 0
                }
            }
        })
        return
    end

    msg.reply({
        Data = {
            vault = userVault
        }
    })
end)

Handlers.add("getUserStabilityPool", "GetUserStabilityPool", function(msg)
    if not msg.From then
        msg.reply({
            Error = "User address is required"
        })
        return
    end

    local value = vaults[msg.From]
    if not value then
        msg.reply({
            Data = {
                stablecoin = 0
            }
        })
        return
    end

    msg.reply({
        Data = {
            stablecoin = value
        }
    })
end)

Handlers.add("getTVL", "GetTVL", function(msg)
    msg.reply({
        Data = {
            TVL = totalCollateral
        }
    })
end)

Handlers.add("getTotalDebt", "GetTotalDebt", function(msg)
    msg.reply({
        Data = {
            totalDebt = totalDebt
        }
    })
end)

Handlers.add("getTotalStabilityPool", "GetTotalStabilityPool", function(msg)
    msg.reply({
        Data = {
            totalStabilityPool = totalStabilityPool
        }
    })
end)

Handlers.add("getUserCount", "GetUserCount", function(msg)
    local count = 0
    for _ in pairs(vaults) do
        count = count + 1
    end
    
    msg.reply({
        Data = {
            userCount = count
        }
    })
end)
