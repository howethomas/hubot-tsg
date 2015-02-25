# A [Hubot](https://github.com/github/hubot) adapter for [TSG](https://www.tsgglobal.com)

## Configuring the Adapter

The TSG adapter requires the account's key as environment variables:
    TSG_SECRET

This version of the adapter won't do automatic registration of numbers. However, when it does, the 
following environment variables are required: 

TSG_CALLBACK_PATH (defaults to "/inbound/tsg")
TSG_LISTEN_PORT (defaults to 80)
TSG_CALLBACK_URL (no default) 

## License

MIT
