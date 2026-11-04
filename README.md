# Rapid Patron Orders

A World of Warcraft (Retail) addon that replaces the **Patron** crafting-orders
list with a profit-ranked list and one-click crafting.

## Features

- **Profit calculator.** Each order shows Reward, Cost, and Profit. Cost is
  the cheapest set of materials you supply that still reaches the order's
  required quality. Reward is the gold plus the market value of tradeable
  reward items.
- **Profit-first sorting.** Click a column header (Order, Reward, Cost,
  Profit, Time) to sort; click again to reverse it.
- **Priority tiers.** Orders you cannot craft always sink to the bottom.
  Above them, you can prioritize orders that need no concentration and orders
  that are profitable. Rows never move while a craft is in progress, so you
  can click the same spot repeatedly.
- **Rapid craft buttons.** Craft (claims the order) → Craft (crafts it) →
  Complete, all clicked in the same spot. While an order is claimed, Release
  appears above that button. Materials you already own are used first, as
  long as they still reach the required quality.
- **Allow concentration** (off by default). Orders that need concentration to
  reach their quality can only be crafted from the list when this is ticked.
  The checkbox is on the Patron list and in the options panel.
- **Allow unprofitable crafts** (off by default). Orders with a negative
  estimated profit can only be crafted from the list when this is ticked.
  It sits next to Allow concentration and is also in the options panel.
- **Augment rune highlight.** Orders that reward a Void-Touched Augment Rune
  get a pulsing purple outline.

The buttons appear only on the Patron tab. Every other tab keeps Blizzard's
normal list.

## Pricing

Uses one of these pricing addons, if installed:

- **TradeSkillMaster**: DBMarket price; for materials, the vendor price when
  it is cheaper.
- **Auctionator**
- **Auctioneer**

By default the first one available is used. You can choose a specific one in
the options. Without a pricing addon, only the gold part of rewards is
counted.

## Options

Open them from *Settings → AddOns → Rapid Patron Orders*, or type `/rpo`.

## Compatibility

Rapid Patron Orders and Crafting Orders++ both replace the Patron list. If
Crafting Orders++ is enabled, Rapid Patron Orders stays inactive and prints a
warning in chat. Enable only one of them.

## Install

Copy the `RapidPatronOrders` folder into
`World of Warcraft/_retail_/Interface/AddOns/`, then `/reload`.

## License

MIT. See [LICENSE](LICENSE).
