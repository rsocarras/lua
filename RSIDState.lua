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
--local newsN;

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
    --newsN = instance:createTextOutput("N", "N", "Arial", 6, core.H_Left, core.V_Bottom, core.rgb(255, 0, 0), 0);
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
        reset();
    end
end
function OverboughtInvalidate(period)
    -- if RSI goes above overbought then the state is invalidated
    if (core.crossesOver(RSI.DATA, Overbought, period)) then
        reset();
    end
end
function BearishDivergence()
    -- second peak price is higher but RSI is lower
    if (peakPrice1 < peakPrice2 and peakRSI1 > peakRSI2) then
        return -1;
    end
    return 0;
end
function BullishDivergence()
    -- second peak price is lower but RSI is higher
    if (peakPrice1 > peakPrice2 and peakRSI1 < peakRSI2) then
        return 1;
    end
    return 0;
end

function LogState(msg, period)
    --newsN:set(period, (period %25), msg);
end

function setState(newState)
    if (newState ~= currentState) then
        currentState = newState;
    end
end

function update(period)
    -- neutral
    local result = 0;
    if (period < first) then
        return result;
    end
    if (currentState == "None") then
        -- RSI into overbought/oversold territory
        if (RSI.DATA[period] > Overbought) then
            -- into overbought
            setState("FirstLongForming", period);
        elseif (RSI.DATA[period] < Oversold) then
            -- into oversold
            setState("FirstShortForming");
        end
        
    elseif (currentState == "FirstLongForming" ) then
        -- during long, keep track the highest RSI and price
        if (src.high[period] > peakPrice1) then
            peakPrice1 = src.high[period];
        end
        if (RSI.DATA[period] > peakRSI1) then
            peakRSI1 = RSI.DATA[period];
        end
        -- if price crosses below the average line then first peak is comleted
        if (src.low[period] < BBavg[period]) then
            setState("FirstLongComplete");
        end
        OversoldInvalidate(period);

    elseif (currentState == "FirstShortForming" ) then
        -- during short, keep track the lowest RSI and price
        if (src.low[period] < peakPrice1 or peakPrice1 == -1) then
            peakPrice1 = src.low[period];
        end
        if (RSI.DATA[period] < peakRSI1 or peakRSI1 == -1) then
            peakRSI1 = RSI.DATA[period];
        end
        -- if price crosses above the average line then first peak is comleted
        if (src.high[period] > BBavg[period]) then
            setState("FirstShortComplete");
        end
        OverboughtInvalidate(period);
        
    elseif (currentState == "FirstLongComplete" ) then
        -- if the price makes a higher high then go to next state
        if (src.high[period] > peakPrice1) then
            peakPrice2 = src.high[period];
            setState("SecondLongForming");
        end
        OversoldInvalidate(period);

    elseif (currentState == "FirstShortComplete" ) then
        -- if the price makes a lower low then go to next state
        if (src.low[period] < peakPrice1) then
            peakPrice2 = src.low[period];
            setState("SecondShortForming");
        end
        OverboughtInvalidate(period);
        
    elseif (currentState == "SecondLongForming" ) then
        -- track the second highest price and RSI
        if (src.high[period] > peakPrice2) then
            peakPrice2 = src.high[period];
        end
        if (RSI.DATA[period] > peakRSI2) then
            peakRSI2 = RSI.DATA[period];
        end
        -- if price crosses below the average line then second peak is completed
        if (src.low[period] < BBavg[period]) then
            setState("SecondLongComplete");
        end
        OversoldInvalidate(period);

    elseif (currentState == "SecondShortForming" ) then
        -- track the second lowest price and RSI
        if (src.low[period] < peakPrice2 or peakPrice2 == -1) then
            peakPrice2 = src.low[period];
        end
        if (RSI.DATA[period] < peakRSI2 or peakRSI2 == -1) then
            peakRSI2 = RSI.DATA[period];
        end
        -- if price crosses above the average line then second peak is completed
        if (src.high[period] > BBavg[period]) then
            setState("SecondShortComplete");
        end
        OverboughtInvalidate(period);
        
    elseif (currentState == "SecondLongComplete" ) then
        result = BearishDivergence();
        -- hitting stop loss
        if (src.close[period] > peakPrice2) then
            reset();
        end
        -- hitting limit
        if (src.low[period] < BBlo[period]) then
            reset();
        end

    elseif (currentState == "SecondShortComplete" ) then
        result = BullishDivergence();
        -- hitting stop loss
        if (src.close[period] < peakPrice2) then
            reset();
        end
        -- hitting limit
        if (src.high[period] > BBhi[period]) then
            reset();
        end

    end
    return result;
end

