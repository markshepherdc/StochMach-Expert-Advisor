
//|                                     Strategy: stochmachcross.mq4 |


#include <stdlib.mqh>
#include <stderror.mqh>

int LotDigits; //initialized in OnInit
int MagicNumber = 1996003;
double TradeSize = 1;
int MaxSlippage = 3; //adjusted in OnInit
bool crossed[8]; //initialized to true, used in function Cross
int MaxOpenTrades = 3;
int MaxLongTrades = 1000;
int MaxShortTrades = 1000;
int MaxPendingOrders = 1000;
bool Hedging = false;
int OrderRetry = 5; //# of retries if sending order returns error
int OrderWait = 5; //# of seconds to wait if sending order returns error
double myPoint; //initialized in OnInit

bool Cross(int i, bool condition) //returns true if "condition" is true and was false in the previous call
  {
   bool ret = condition && !crossed[i];
   crossed[i] = condition;
   return(ret);
  }

void myAlert(string type, string message)
  {
   if(type == "print")
      Print(message);
   else if(type == "error")
     {
      Print(type+" | stochmachcross @ "+Symbol()+","+Period()+" | "+message);
     }
   else if(type == "order")
     {
     }
   else if(type == "modify")
     {
     }
  }

int TradesCount(int type) //returns # of open trades for order type, current symbol and magic number
  {
   int result = 0;
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false) continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol() || OrderType() != type) continue;
      result++;
     }
   return(result);
  }

int myOrderSend(int type, double price, double volume, string ordername) //send order, return ticket ("price" is irrelevant for market orders)
  {
   if(!IsTradeAllowed()) return(-1);
   int ticket = -1;
   int retries = 0;
   int err;
   int long_trades = TradesCount(OP_BUY);
   int short_trades = TradesCount(OP_SELL);
   int long_pending = TradesCount(OP_BUYLIMIT) + TradesCount(OP_BUYSTOP);
   int short_pending = TradesCount(OP_SELLLIMIT) + TradesCount(OP_SELLSTOP);
   string ordername_ = ordername;
   if(ordername != "")
      ordername_ = "("+ordername+")";
   //test Hedging
   if(!Hedging && ((type % 2 == 0 && short_trades + short_pending > 0) || (type % 2 == 1 && long_trades + long_pending > 0)))
     {
      myAlert("print", "Order"+ordername_+" not sent, hedging not allowed");
      return(-1);
     }
   //test maximum trades
   if((type % 2 == 0 && long_trades >= MaxLongTrades)
   || (type % 2 == 1 && short_trades >= MaxShortTrades)
   || (long_trades + short_trades >= MaxOpenTrades)
   || (type > 1 && long_pending + short_pending >= MaxPendingOrders))
     {
      myAlert("print", "Order"+ordername_+" not sent, maximum reached");
      return(-1);
     }
   //prepare to send order
   while(IsTradeContextBusy()) Sleep(100);
   RefreshRates();
   if(type == OP_BUY)
      price = Ask;
   else if(type == OP_SELL)
      price = Bid;
   else if(price < 0) //invalid price for pending order
     {
      myAlert("order", "Order"+ordername_+" not sent, invalid price for pending order");
	  return(-1);
     }
   int clr = (type % 2 == 1) ? clrRed : clrBlue;
   while(ticket < 0 && retries < OrderRetry+1)
     {
      ticket = OrderSend(Symbol(), type, NormalizeDouble(volume, LotDigits), NormalizeDouble(price, Digits()), MaxSlippage, 0, 0, ordername, MagicNumber, 0, clr);
      if(ticket < 0)
        {
         err = GetLastError();
         myAlert("print", "OrderSend"+ordername_+" error #"+err+" "+ErrorDescription(err));
         Sleep(OrderWait*1000);
        }
      retries++;
     }
   if(ticket < 0)
     {
      myAlert("error", "OrderSend"+ordername_+" failed "+(OrderRetry+1)+" times; error #"+err+" "+ErrorDescription(err));
      return(-1);
     }
   string typestr[6] = {"Buy", "Sell", "Buy Limit", "Sell Limit", "Buy Stop", "Sell Stop"};
   myAlert("order", "Order sent"+ordername_+": "+typestr[type]+" "+Symbol()+" Magic #"+MagicNumber);
   return(ticket);
  }

void myOrderClose(int type, int volumepercent, string ordername) //close open orders for current symbol, magic number and "type" (OP_BUY or OP_SELL)
  {
   if(!IsTradeAllowed()) return;
   if (type > 1)
     {
      myAlert("error", "Invalid type in myOrderClose");
      return;
     }
   bool success = false;
   int err;
   string ordername_ = ordername;
   if(ordername != "")
      ordername_ = "("+ordername+")";
   int total = OrdersTotal();
   for(int i = total-1; i >= 0; i--)
     {
      while(IsTradeContextBusy()) Sleep(100);
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol() || OrderType() != type) continue;
      while(IsTradeContextBusy()) Sleep(100);
      RefreshRates();
      double price = (type == OP_SELL) ? Ask : Bid;
      double volume = NormalizeDouble(OrderLots()*volumepercent * 1.0 / 100, LotDigits);
      if (NormalizeDouble(volume, LotDigits) == 0) continue;
      success = OrderClose(OrderTicket(), volume, NormalizeDouble(price, Digits()), MaxSlippage, clrWhite);
      if(!success)
        {
         err = GetLastError();
         myAlert("error", "OrderClose"+ordername_+" failed; error #"+err+" "+ErrorDescription(err));
        }
     }
   string typestr[6] = {"Buy", "Sell", "Buy Limit", "Sell Limit", "Buy Stop", "Sell Stop"};
   if(success) myAlert("order", "Orders closed"+ordername_+": "+typestr[type]+" "+Symbol()+" Magic #"+MagicNumber);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {   
   //initialize myPoint
   myPoint = Point();
   if(Digits() == 5 || Digits() == 3)
     {
      myPoint *= 10;
      MaxSlippage *= 10;
     }
   //initialize LotDigits
   double LotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(LotStep >= 1) LotDigits = 0;
   else if(LotStep >= 0.1) LotDigits = 1;
   else if(LotStep >= 0.01) LotDigits = 2;
   else LotDigits = 3;
   int i;
   //initialize crossed
   for (i = 0; i < ArraySize(crossed); i++)
      crossed[i] = true;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   int ticket = -1;
   double price;   
   
   
   //Close Long Positions, instant signal is tested first
   if(Cross(2, iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_MAIN, 0) < iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_SIGNAL, 0)) //Stochastic Oscillator crosses below Stochastic Oscillator
   )
     {   
      if(IsTradeAllowed())
         myOrderClose(OP_BUY, 100, "");
      else //not autotrading => only send alert
         myAlert("order", "");
     }
   
   //Close Long Positions, instant signal is tested first
   if(Cross(3, iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0) < iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0)) //MACD crosses below MACD
   )
     {   
      if(IsTradeAllowed())
         myOrderClose(OP_BUY, 100, "");
      else //not autotrading => only send alert
         myAlert("order", "");
     }
   
   //Close Short Positions, instant signal is tested first
   if(Cross(0, iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_MAIN, 0) > iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_SIGNAL, 0)) //Stochastic Oscillator crosses above Stochastic Oscillator
   )
     {   
      if(IsTradeAllowed())
         myOrderClose(OP_SELL, 100, "");
      else //not autotrading => only send alert
         myAlert("order", "");
     }
   
   //Close Short Positions, instant signal is tested first
   if(Cross(1, iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0) > iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0)) //MACD crosses above MACD
   )
     {   
      if(IsTradeAllowed())
         myOrderClose(OP_SELL, 100, "");
      else //not autotrading => only send alert
         myAlert("order", "");
     }
   
   //Open Buy Order, instant signal is tested first
   if(Cross(4, iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_MAIN, 0) > iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_SIGNAL, 0)) //Stochastic Oscillator crosses above Stochastic Oscillator
   && iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0) > iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0) //MACD > MACD
   )
     {
      RefreshRates();
      price = Ask;   
      if(IsTradeAllowed())
        {
         ticket = myOrderSend(OP_BUY, price, TradeSize, "");
         if(ticket <= 0) return;
        }
      else //not autotrading => only send alert
         myAlert("order", "");
     }
   
   //Open Buy Order, instant signal is tested first
   if(Cross(5, iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0) > iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0)) //MACD crosses above MACD
   && iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_MAIN, 0) > iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_MAIN, 0) //Stochastic Oscillator > Stochastic Oscillator
   )
     {
      RefreshRates();
      price = Ask;   
      if(IsTradeAllowed())
        {
         ticket = myOrderSend(OP_BUY, price, TradeSize, "");
         if(ticket <= 0) return;
        }
      else //not autotrading => only send alert
         myAlert("order", "");
     }
   
   //Open Sell Order, instant signal is tested first
   if(Cross(6, iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_MAIN, 0) < iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_SIGNAL, 0)) //Stochastic Oscillator crosses below Stochastic Oscillator
   && iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0) < iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0) //MACD < MACD
   )
     {
      RefreshRates();
      price = Bid;   
      if(IsTradeAllowed())
        {
         ticket = myOrderSend(OP_SELL, price, TradeSize, "");
         if(ticket <= 0) return;
        }
      else //not autotrading => only send alert
         myAlert("order", "");
     }
   
   //Open Sell Order, instant signal is tested first
   if(Cross(7, iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0) < iMACD(NULL, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0)) //MACD crosses below MACD
   && iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_MAIN, 0) < iStochastic(NULL, PERIOD_CURRENT, 3, 3, 8, MODE_SMA, 0, MODE_MAIN, 0) //Stochastic Oscillator < Stochastic Oscillator
   )
     {
      RefreshRates();
      price = Bid;   
      if(IsTradeAllowed())
        {
         ticket = myOrderSend(OP_SELL, price, TradeSize, "");
         if(ticket <= 0) return;
        }
      else //not autotrading => only send alert
         myAlert("order", "");
     }
  }
//+------------------------------------------------------------------+