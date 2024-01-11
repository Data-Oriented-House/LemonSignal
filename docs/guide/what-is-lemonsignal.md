# What is LemonSignal?

`LemonSignal` is a pure Luau signal implementation that works both outside and inside Roblox without sacrificing performance, for Roblox it is aimed at replacing [GoodSignal](https://github.com/stravant/goodsignal) and [BindableEvent](https://create.roblox.com/docs/reference/engine/classes/BindableEvent), it has performance improvements over them and houses new features like variadic connections and the ability to reconnect disconnected connections using `:Reconnect`.
More on those features on the next page.

## API Design
`LemonSignal` uses the conventional Roblox signal and connection so you can easily swap it with any other Luau signal that uses that API like `GoodSignal` and immediately enjoy the new features and optimizations.
