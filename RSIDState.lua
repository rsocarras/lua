module("RSIDState", package.seeall)


local currentState;
local Overbought = 70;
local Oversold = 30;

local src = nil;
local RSI = nil;
local BBavg = nil;
local BBhi = nil;
local BBlo = nil;
local BB = nil;

local peakPrice1 = -1;
local peakRSI1 = -1;
local peakPrice2 = -1;
local peakRSI2 = -1;
local first;

-- Possible states:
-- None
-- FirstLongForming
-- FirstLongComplete
-- SecondLongForming
-- SecondLongComplete
-- FirstShortForming
-- FirstShortComplete
-- SecondShortForming
-- SecondShortComplete
-- Return one of the above states, based
-- on current values

function init(sourceStream, rsiStream, bbStream)
    src = sourceStream;
    RSI = rsiStream;
    BB = bbStream;
    BBhi =  BB:getStream(0);
    BBlo =  BB:getStream(1);
    BBavg = BB:getStream(2);
    currentState = "None";
    first = math.max(RSI.DATA:first(), BB.DATA:first()) + 1;
end

function reset()
    currentState = "None";
    peakPrice1 = -1;
    peakRSI1 = -1;
    peakPrice2 = -1;
    peakRSI2 = -1;
end
function OversoldInvalidate(period)
    -- if RSI goes below oversold then the state is invalidated
    if (core.crossesUnder(RSI.DATA, Oversold, period)) then
        core.host:trace("RSIDState.OversoldInvalidate: " .. RSI.DATA[period]);
        reset();
    end
end
function OverboughtInvalidate(period)
    -- if RSI goes above overbought then the state is invalidated
    if (core.crossesOver(RSI.DATA, Overbought, period)) then
        core.host:trace("RSIDState.OverboughtInvalidate: " .. RSI.DATA[period]);
        reset();
    end
end
function BearishDivergence()
    -- second peak price is higher but RSI is lower
    if (peakPrice1 < peakPrice2 and peakRSI1 > peakRSI2) then
        core.host:trace("RSIDState.BearishDivergence: Prc1: " .. peakPrice1 .. ", Prc2: " .. peakPrice2 .. ", RSI1: " .. peakRSI1 .. ", RSI2: " .. peakRSI2);
        return -1;
    end
    return 0;
end
function BullishDivergence()
    -- second peak price is lower but RSI is higher
    if (peakPrice1 > peakPrice2 and peakRSI1 < peakRSI2) then
        core.host:trace("RSIDState.BullishDivergence: Prc1: " .. peakPrice1 .. ", Prc2: " .. peakPrice2 .. ", RSI1: " .. peakRSI1 .. ", RSI2: " .. peakRSI2);
        return 1;
    end
    return 0;
end
function LogState(period)
    core.host:trace("RSIDState: " .. currentState ..
        ", Prc1: " .. peakPrice1   .. ", Prc2: " .. peakPrice2    ..
        ", RSI1: " .. peakRSI1     .. ", RSI2: " .. peakRSI2      .. ", RSI: "  .. RSI.DATA[period] ..
        ", BBhi: " .. BBhi[period] .. ", BBav: " .. BBavg[period] .. ", BBlo: " .. BBlo[period]
    );
end

function update(period)
    -- neutral
    local result = 0;
    if (period < first) then
        return result;
    end
    if (currentState == "None") then
        LogState(period);
        -- RSI into overbought/oversold territory
        if (core.crossesOver(RSI.DATA, Overbought, period)) then
            -- into overbought
            currentState = "FirstLongForming";
        elseif (core.crossesUnder(RSI.DATA, Oversold, period)) then
            -- into oversold
            currentState = "FirstShortForming";
        end
        
    elseif (currentState == "FirstLongForming" ) then
        LogState(period);
        -- during long, keep track the highest RSI and price
        if (src[period] > peakPrice1) then
            peakPrice1 = src[period];
        end
        if (RSI.DATA[period] > peakRSI1) then
            peakRSI1 = RSI.DATA[period];
        end
        -- if price crosses below the average line then first peak is comleted
        if (core.crossesUnder(src, BBavg, period)) then
            currentState = "FirstLongComplete";
        end
        OversoldInvalidate(period);

    elseif (currentState == "FirstShortForming" ) then
        LogState(period);
        -- during short, keep track the lowest RSI and price
        if (src[period] < peakPrice1 or peakPrice1 == -1) then
            peakPrice1 = src[period];
        end
        if (RSI.DATA[period] < peakRSI1 or peakRSI1 == -1) then
            peakRSI1 = RSI.DATA[period];
        end
        -- if price crosses below the average line then first peak is comleted
        if (core.crossesOver(src, BBavg, period)) then
            currentState = "FirstShortComplete";
        end
        OverboughtInvalidate(period);
        
    elseif (currentState == "FirstLongComplete" ) then
        LogState(period);
        -- if the price makes a higher high then go to next state
        if (src[period] > peakPrice1) then
            currentState = "SecondLongForming";
        end
        OversoldInvalidate(period);

    elseif (currentState == "FirstShortComplete" ) then
        LogState(period);
        -- if the price makes a lower low then go to next state
        if (src[period] < peakPrice1) then
            currentState = "SecondShortForming";
        end
        OverboughtInvalidate(period);
        
    elseif (currentState == "SecondLongForming" ) then
        LogState(period);
        -- track the second highest price and RSI
        if (src[period] > peakPrice2) then
            peakPrice2 = src[period];
        end
        if (RSI.DATA[period] > peakRSI2) then
            peakRSI2 = RSI.DATA[period];
        end
        -- if price crosses below the average line then second peak is completed
        if (core.crossesUnder(src, BBavg, period)) then
            currentState = "SecondLongComplete";
        end
        OversoldInvalidate(period);

    elseif (currentState == "SecondShortForming" ) then
        LogState(period);
        -- track the second lowest price and RSI
        if (src[period] < peakPrice2 or peakPrice2 == -1) then
            peakPrice2 = src[period];
        end
        if (RSI.DATA[period] < peakRSI2 or peakRSI2 == -1) then
            peakRSI2 = RSI.DATA[period];
        end
        -- if price crosses above the average line then second peak is completed
        if (core.crossesOver(src, BBavg, period)) then
            currentState = "SecondShortComplete";
        end
        OverboughtInvalidate(period);
        
    elseif (currentState == "SecondLongComplete" ) then
        LogState(period);
        result = BearishDivergence();
        -- hitting stop loss
        if (src[period] > peakPrice2) then
            reset();
        end
        -- hitting limit
        if (core.crossesUnder(src, BBlo, period)) then
            reset();
        end

    elseif (currentState == "SecondShortComplete" ) then
        LogState(period);
        result = BullishDivergence();
        -- hitting stop loss
        if (src[period] < peakPrice2) then
            reset();
        end
        -- hitting limit
        if (core.crossesOver(src, BBhi, period)) then
            reset();
        end

    end
    return result;
end

