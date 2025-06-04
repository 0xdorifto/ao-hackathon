-- require json module
local json = require("json")

--[[
  Functions:
    Troves:
      - DepositCollateral (create vault for user if it doesn't exist, deposit collateral into vault)
      - WithdrawCollateral (withdraw collateral from vault if collateral ratio is above minimum)
      - MintStablecoin (mint stablecoin if collateral ratio is above minimum)
      - RepayStablecoin (repay stablecoin if collateral ratio is above minimum)
    Stability Pool:
      - DepositStablecoin (deposit stablecoin into stability pool)
      - WithdrawStablecoin (withdraw stablecoin from stability pool)
    Liquidation:
      - PerformLiquidation (cron job that checks for undercollateralized vaults and liquidates them every minute)
    Getters:
      - GetTotalSupply (TVL) (returns total amount of collateral in the protocol)
      - GetStablecoinSupply (returns total amount of stablecoin in circulation)
      - GetBorrowingFee (returns the borrowing fee)
      - GetUserVault (returns the vault for a user)

    do redemptions later
]]
--

-- State variables
-- vaults: maps user address to { collateral: number, debt: number, collateralRatio: number }
local vaults = vaults or {}
-- stabilityPool: maps user address to { deposit: number, collateralGain: number, stablecoinGain: number }
local stabilityPool = stabilityPool or {}
local stablecoinSupply = stablecoinSupply or 0
local lastLiquidationTime = lastLiquidationTime or 0
local liquidationInterval = 60 -- 60 seconds between liquidation checks

-- Configuration (replace with actual AO token ID)
local collateralTokenId = "3u52R0MlntHPBKA_Su5qptUtS-3dxtc_dfvGAiLU6PAs"
local stablecoinTokenId = "7RNnoihSI4s3FF4vcGhZ6RRF-bwvhtSSPLqX05L-JOs"
local minimumCollateralRatio = 1.1 -- 110% minimum collateral ratio
local borrowingFee = 0.01 -- 1% borrowing fee
local redemptionFee = 0.005 -- 0.5%
local baseRate = 0 -- Dynamic base rate for borrowing fee

-- Helper function to calculate collateral ratio
-- Assumes a fixed price for simplicity. A real system needs an oracle.
-- Ratio = (collateral_amount * collateral_price) / debt_amount
-- Since we don't have a price feed, we'll calculate based on a conceptual ratio
-- For this example, let's assume 1 AO = 1 STC for ratio calculation purposes only.
-- A real implementation would need a reliable price feed.
local function calculateCollateralRatio(collateral, debt)
  if debt == 0 then
    return math.huge -- Infinite ratio if no debt
  end
  -- In a real system, collateral would be multiplied by its price here
  return collateral / debt
end

-- Helper function to calculate borrowing fee
local function calculateBorrowingFee(amount)
  return amount * (baseRate + borrowingFee)
end

-- Helper function to calculate redemption fee
local function calculateRedemptionFee(amount)
  return amount * redemptionFee
end

-- Helper function to perform liquidation
local function liquidateVault(vaultAddress)
  local vault = vaults[vaultAddress]
  if not vault or vault.debt == 0 then
    return "Vault not found or has no debt."
  end

  local currentRatio = calculateCollateralRatio(vault.collateral, vault.debt)
  if currentRatio >= minimumCollateralRatio then
    return "Vault is not undercollateralized."
  end

  -- Calculate liquidation amount (e.g., 100% of debt)
  local liquidationAmount = vault.debt
  local collateralSeized = vault.collateral -- Simplified: seize all collateral for now

  -- Distribute seized collateral and stablecoin debt to stability pool participants
  local totalStabilityPoolDeposit = 0
  for _, data in pairs(stabilityPool) do
    totalStabilityPoolDeposit = totalStabilityPoolDeposit + data.deposit
  end

  if totalStabilityPoolDeposit == 0 then
    -- No stability pool to liquidate against
    return "No funds in stability pool for liquidation."
  end

  local collateralPerUnit = collateralSeized / totalStabilityPoolDeposit
  local stablecoinPerUnit = liquidationAmount / totalStabilityPoolDeposit

  for participant, data in pairs(stabilityPool) do
    local share = data.deposit
    stabilityPool[participant].collateralGain = (stabilityPool[participant].collateralGain or 0) + (share * collateralPerUnit)
    -- Stability pool participants absorb the debt, reducing their effective stablecoin balance in the pool
    stabilityPool[participant].stablecoinGain = (stabilityPool[participant].stablecoinGain or 0) - (share * stablecoinPerUnit)
  end

  -- Update vault state
  vaults[vaultAddress].collateral = 0 -- All collateral seized
  vaults[vaultAddress].debt = 0 -- Debt covered by stability pool

  -- Reduce total stablecoin supply by the liquidated debt
  stablecoinSupply = stablecoinSupply - liquidationAmount

  -- Update base rate for future borrowing fees
  baseRate = baseRate + 0.01 -- Increase base rate by 1% after each liquidation

  return string.format("Vault %s liquidated. Collateral seized: %f, Debt covered: %f",
                       vaultAddress, collateralSeized, liquidationAmount)
end

-- Handler for incoming Credit-Notice messages (for collateral deposits)
Handlers.add(
  "CreditNotice",
  Handlers.utils.hasMatchingTag("Action", "Credit-Notice"),
  function (msg)
    -- Ensure the credit notice is from the designated collateral token process
    if msg["From-Process"] ~= collateralTokenId then
      print("Received Credit-Notice from untrusted process: " .. msg["From-Process"])
      return
    end

    local sender = msg.Tags.Sender -- The user who sent the collateral
    local quantity = tonumber(msg.Tags.Quantity)

    if not sender or not quantity or quantity <= 0 then
      print("Invalid Credit-Notice message.")
      return
    end

    if not vaults[sender] then
      vaults[sender] = { collateral = 0, debt = 0 }
    end

    vaults[sender].collateral = vaults[sender].collateral + quantity
    print(string.format("Received %f collateral from %s. New balance: %f", quantity, sender, vaults[sender].collateral))

    -- Optionally, send a confirmation back to the sender
    ao.send({
      Target = sender,
      Tags = {
        ["Action"] = "CollateralDeposited",
        ["Quantity"] = tostring(quantity),
        ["CollateralToken"] = collateralTokenId
      }
    })
  end
)

-- Handler for depositing collateral (user sends message to this process, then sends AO token)
Handlers.add(
  "DepositCollateral",
  "DepositCollateral",
  function (msg)
    -- User needs to send the AO token to this process after sending this message.
    -- The actual collateral update happens in the Credit-Notice handler.
    -- This handler just acknowledges the user's intent.
    ao.send({
      Target = msg.From,
      Tags = {
        ["Action"] = "AcknowledgeDeposit",
        ["Message"] = "Please send your AO collateral to this process: " .. ao.id
      }
    })
  end
)

-- Handler for minting stablecoin
Handlers.add(
  "MintStablecoin",
  "MintStablecoin",
  function (msg)
    local minter = msg.From
    local quantity = tonumber(msg.Tags.Quantity)

    if not vaults[minter] or vaults[minter].collateral == 0 then
      ao.send({ Target = minter, Tags = { ["Action"] = "MintFailed", ["Message"] = "No collateral deposited." } })
      return
    end

    if not quantity or quantity <= 0 then
      ao.send({ Target = minter, Tags = { ["Action"] = "MintFailed", ["Message"] = "Invalid mint quantity." } })
      return
    end

    local newDebt = vaults[minter].debt + quantity
    local currentCollateral = vaults[minter].collateral
    local newRatio = calculateCollateralRatio(currentCollateral, newDebt)

    if newRatio < minimumCollateralRatio then
      ao.send({ Target = minter, Tags = { ["Action"] = "MintFailed", ["Message"] = "Minting this quantity would result in an undercollateralized vault." } })
      return
    end

    vaults[minter].debt = newDebt
    stablecoinSupply = stablecoinSupply + quantity

    ao.send({
      Target = minter,
      Tags = {
        ["Action"] = "StablecoinMinted",
        ["Quantity"] = tostring(quantity),
        ["NewDebt"] = tostring(newDebt),
        ["NewRatio"] = tostring(newRatio)
      }
    })
    print(string.format("%s minted %f STC. New debt: %f, New ratio: %f", minter, quantity, newDebt, newRatio))
  end
)

-- Modify Credit-Notice handler to also handle incoming STC for Stability Pool
local originalCreditNoticeHandler = Handlers.list["CreditNotice"].handler
Handlers.list["CreditNotice"].handler = function(msg)
  if msg["From-Process"] == ao.id then
    -- This is an incoming STC transfer (likely for Stability Pool)
    local sender = msg.Tags.Sender -- The user who sent the STC
    local quantity = tonumber(msg.Tags.Quantity)

    if not sender or not quantity or quantity <= 0 then
      print("Invalid STC Credit-Notice message.")
      return
    end

    if not stabilityPool[sender] then
      stabilityPool[sender] = { deposit = 0, collateralGain = 0, stablecoinGain = 0 }
    end

    stabilityPool[sender].deposit = stabilityPool[sender].deposit + quantity
    print(string.format("Received %f STC for Stability Pool from %s. New deposit: %f", quantity, sender, stabilityPool[sender].deposit))

    -- Optionally, send a confirmation back to the sender
    ao.send({
      Target = sender,
      Tags = {
        ["Action"] = "StabilityPoolDeposited",
        ["Quantity"] = tostring(quantity),
        ["Stablecoin"] = ao.id
      }
    })

  else
    -- This is a Credit-Notice from another process (e.g., collateral token)
    originalCreditNoticeHandler(msg)
  end
end


-- Handler for triggering liquidation
Handlers.add(
  "Liquidate",
  Handlers.utils.hasMatchingTag("Action", "Liquidate"),
  function (msg)
    local targetVault = msg.Tags.TargetVault
    if not targetVault then
      ao.send({ Target = msg.From, Tags = { ["Action"] = "LiquidateFailed", ["Message"] = "TargetVault tag is required." } })
      return
    end

    local resultMsg = liquidateVault(targetVault)
    ao.send({ Target = msg.From, Tags = { ["Action"] = "LiquidationResult", ["Message"] = resultMsg } })
    print("Liquidation attempt result: " .. resultMsg)
  end
)

-- Handler to get a specific vault's state
Handlers.add(
  "GetVaultState",
  Handlers.utils.hasMatchingTag("Action", "GetVaultState"),
  function (msg)
    local target = msg.Tags.Target or msg.From
    local state = vaults[target] or { collateral = 0, debt = 0 }
    local ratio = calculateCollateralRatio(state.collateral, state.debt)
    ao.send({
      Target = msg.From,
      Data = json.encode({
        collateral = state.collateral,
        debt = state.debt,
        ratio = ratio,
        isUndercollateralized = ratio < minimumCollateralRatio
      })
    })
  end
)

-- Handler to get Stability Pool state
Handlers.add(
  "GetStabilityPoolState",
  Handlers.utils.hasMatchingTag("Action", "GetStabilityPoolState"),
  function (msg)
     local target = msg.Tags.Target or msg.From
     local state = stabilityPool[target] or { deposit = 0, collateralGain = 0, stablecoinGain = 0 }
     local totalDeposit = 0
     for _, data in pairs(stabilityPool) do
       totalDeposit = totalDeposit + data.deposit
     end

     ao.send({
       Target = msg.From,
       Data = json.encode({
         userDeposit = state.deposit,
         userCollateralGain = state.collateralGain,
         userStablecoinGain = state.stablecoinGain,
         totalPoolDeposit = totalDeposit
       })
     })
  end
)

-- Handler to get total stablecoin supply
Handlers.add(
  "GetTotalSupply",
  Handlers.utils.hasMatchingTag("Action", "GetTotalSupply"),
  function (msg)
    ao.send({
      Target = msg.From,
      Data = json.encode({ totalSupply = stablecoinSupply })
    })
  end
)

-- Handler to get total collateral in the protocol
Handlers.add(
  "GetTotalCollateral",
  Handlers.utils.hasMatchingTag("Action", "GetTotalCollateral"),
  function (msg)
    local totalCollateral = 0
    for _, vault in pairs(vaults) do
      totalCollateral = totalCollateral + vault.collateral
    end
    ao.send({
      Target = msg.From,
      Data = json.encode({ totalCollateral = totalCollateral })
    })
  end
)

--[[
     WithdrawCollateral
   ]]
--
Handlers.add('withdrawCollateral', "WithdrawCollateral", function(msg)
  local quantity = tonumber(msg.Tags.Quantity)
  local sender = msg.From

  -- Validate input
  if not quantity or quantity <= 0 then
    ao.send({
      Target = sender,
      Tags = {
        ["Action"] = "WithdrawFailed",
        ["Message"] = "Invalid withdrawal amount"
      }
    })
    return
  end

  -- Check if user has a vault
  if not vaults[sender] then
    ao.send({
      Target = sender,
      Tags = {
        ["Action"] = "WithdrawFailed",
        ["Message"] = "No vault found"
      }
    })
    return
  end

  -- Check if user has enough collateral
  if vaults[sender].collateral < quantity then
    ao.send({
      Target = sender,
      Tags = {
        ["Action"] = "WithdrawFailed",
        ["Message"] = "Insufficient collateral balance"
      }
    })
    return
  end

  -- Calculate new collateral ratio after withdrawal
  local newCollateral = vaults[sender].collateral - quantity
  local newRatio = calculateCollateralRatio(newCollateral, vaults[sender].debt)

  -- Check if withdrawal would make vault undercollateralized
  if newRatio < minimumCollateralRatio and vaults[sender].debt > 0 then
    ao.send({
      Target = sender,
      Tags = {
        ["Action"] = "WithdrawFailed",
        ["Message"] = "Withdrawal would make vault undercollateralized"
      }
    })
    return
  end

  -- Update vault balance
  vaults[sender].collateral = newCollateral

  -- Send AO tokens back to user
  ao.send({
    Target = aoProcessId,
    Tags = {
      ["Action"] = "Transfer",
      ["Recipient"] = sender,
      ["Quantity"] = tostring(quantity)
    }
  })

  -- Send confirmation
  ao.send({
    Target = sender,
    Tags = {
      ["Action"] = "CollateralWithdrawn",
      ["Quantity"] = tostring(quantity),
      ["NewBalance"] = tostring(newCollateral)
    }
  })
end)

-- Handler for repaying stablecoin debt
Handlers.add(
  "RepayStablecoin",
  Handlers.utils.hasMatchingTag("Action", "RepayStablecoin"),
  function(msg)
    local repayer = msg.From
    local quantity = tonumber(msg.Tags.Quantity)

    if not quantity or quantity <= 0 then
      ao.send({
        Target = repayer,
        Tags = {
          ["Action"] = "RepayFailed",
          ["Message"] = "Invalid repayment amount."
        }
      })
      return
    end

    if not vaults[repayer] or vaults[repayer].debt == 0 then
      ao.send({
        Target = repayer,
        Tags = {
          ["Action"] = "RepayFailed",
          ["Message"] = "No debt to repay."
        }
      })
      return
    end

    -- Calculate actual repayment amount (including any fees)
    local actualRepayment = math.min(quantity, vaults[repayer].debt)
    local newDebt = vaults[repayer].debt - actualRepayment

    -- Update vault state
    vaults[repayer].debt = newDebt
    stablecoinSupply = stablecoinSupply - actualRepayment

    -- Send confirmation
    ao.send({
      Target = repayer,
      Tags = {
        ["Action"] = "StablecoinRepaid",
        ["Quantity"] = tostring(actualRepayment),
        ["NewDebt"] = tostring(newDebt),
        ["NewRatio"] = tostring(calculateCollateralRatio(vaults[repayer].collateral, newDebt))
      }
    })
  end
)

-- Handler for depositing into Stability Pool
Handlers.add(
  "DepositStabilityPool",
  Handlers.utils.hasMatchingTag("Action", "DepositStabilityPool"),
  function (msg)
    -- User needs to send the STC token (this process's ID) to this process after sending this message.
    -- The actual stability pool update happens in the Credit-Notice handler when msg["From-Process"] is ao.id.
    -- This handler just acknowledges the user's intent.
     ao.send({
      Target = msg.From,
      Tags = {
        ["Action"] = "AcknowledgeStabilityPoolDeposit",
        ["Message"] = "Please send your STC to this process: " .. ao.id
      }
    })
  end
)

-- Handler for withdrawing from Stability Pool
Handlers.add(
  "WithdrawStabilityPool",
  Handlers.utils.hasMatchingTag("Action", "WithdrawStabilityPool"),
  function(msg)
    local withdrawer = msg.From
    local quantity = tonumber(msg.Tags.Quantity)

    if not quantity or quantity <= 0 then
      ao.send({
        Target = withdrawer,
        Tags = {
          ["Action"] = "WithdrawFailed",
          ["Message"] = "Invalid withdrawal amount."
        }
      })
      return
    end

    if not stabilityPool[withdrawer] or stabilityPool[withdrawer].deposit < quantity then
      ao.send({
        Target = withdrawer,
        Tags = {
          ["Action"] = "WithdrawFailed",
          ["Message"] = "Insufficient deposit in stability pool."
        }
      })
      return
    end

    -- Calculate proportional gains
    local totalDeposit = stabilityPool[withdrawer].deposit
    local collateralGain = stabilityPool[withdrawer].collateralGain * (quantity / totalDeposit)
    local stablecoinGain = stabilityPool[withdrawer].stablecoinGain * (quantity / totalDeposit)

    -- Update stability pool state
    stabilityPool[withdrawer].deposit = stabilityPool[withdrawer].deposit - quantity
    stabilityPool[withdrawer].collateralGain = stabilityPool[withdrawer].collateralGain - collateralGain
    stabilityPool[withdrawer].stablecoinGain = stabilityPool[withdrawer].stablecoinGain - stablecoinGain

    -- Send confirmation
    ao.send({
      Target = withdrawer,
      Tags = {
        ["Action"] = "StabilityPoolWithdrawn",
        ["Quantity"] = tostring(quantity),
        ["CollateralGain"] = tostring(collateralGain),
        ["StablecoinGain"] = tostring(stablecoinGain)
      }
    })
  end
)

-- Handler for getting borrowing fee
Handlers.add(
  "GetBorrowingFee",
  Handlers.utils.hasMatchingTag("Action", "GetBorrowingFee"),
  function(msg)
    ao.send({
      Target = msg.From,
      Data = json.encode({
        baseRate = baseRate,
        borrowingFee = borrowingFee,
        totalFee = baseRate + borrowingFee
      })
    })
  end
)

-- Cron job for liquidation checks
Handlers.add(
  "Cron",
  Handlers.utils.hasMatchingTag("Action", "Cron"),
  function(msg)
    local currentTime = os.time()
    if currentTime - lastLiquidationTime >= liquidationInterval then
      lastLiquidationTime = currentTime
      
      -- Check all vaults for liquidation
      for vaultAddress, vault in pairs(vaults) do
        if vault.debt > 0 then
          local ratio = calculateCollateralRatio(vault.collateral, vault.debt)
          if ratio < minimumCollateralRatio then
            liquidateVault(vaultAddress)
          end
        end
      end
    end
  end
)

-- Call oracle to get collateral price
local function getCollateralPrice()
  local data = ao.send({Target = "R5rRjBFS90qIGaohtzd1IoyPwZD0qJZ25QXkP7_p5a0" , Action = "v1.Info"}).receive().Data
  local value = data.Prices[20].qAR.verifiedPackage.v
  return value
end

print("Stalecoin Protocol Process Initialized. Process ID: " .. ao.id)