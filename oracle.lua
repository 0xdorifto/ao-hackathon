local json = require("json")

collateralTokenId = "3u52R0MlntHPBKA_Su5qptUtS-3dxtc_dfvGAiLU6PAs"
stablecoinTokenId = "7RNnoihSI4s3FF4vcGhZ6RRF-bwvhtSSPLqX05L-JOs"
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
    end
)
