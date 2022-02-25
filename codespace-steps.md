# Hack Club Bank Install on Codespaces

GitHub Codespaces comes preinstalled with Docker, so the following steps should work as long as you spin up a new codespace. These instructions may also work on a local machine but will need the prerequisite dependencies and may run into some errors.

After a bit of testing, I haven't seen a big difference between the different codespace options (2 cores vs 16 cores), so I recommend starting with the cheapest option and upgrading it if your instance is feeling slow.

## Prerequisites

A modern browser + internet & a good attitude.

## Steps

0. Whip up a Codespace instance. [GitHub's docs](https://docs.github.com/en/codespaces/getting-started/quickstart) are kept up-to-date on this.
1. Fill in the `config/master.key` file. If you don't have one, reach out to a Bank dev team member who can give you one.
2. Run `codespace-config.sh`
    - Optional: append the `--with-solargraph` flag to enable [Solargraph](https://solargraph.org/demo), a tool that provides IntelliSense, autocompletion, and inline documentation for Ruby in VS Code.
    - You may also need to install the [Ruby Solargraph](https://marketplace.visualstudio.com/items?itemName=castwide.solargraph) VS Code extension in order to use Solargraph.
3. Login with Heroku username & password when prompted. You need to be added to the Heroku project; reach out to a Bank dev team member to be added.
4. Go cook some pasta or something, this will load for a long time
5. Enjoy my beautiful eye candy -kunal
6. Profit
7. Your codespace should be all configured to run a dev environment.

## Developing on Codespaces

You can now spin up the server by running `codespace-start.sh` or with this command:
`env $(cat .env.docker) docker-compose run --service-ports web`

Run `codespace-start.sh` with the `--with-solargraph` flag to start your dev server with Solargraph.

Or, enter an interactive shell in the docker container:
`env $(cat .env.docker) docker-compose run --service-ports web /bin/bash`

When you run the server, Codespaces should automatically notify you that port 3000 has been forwarded and give you a preview link. If it doesn't, you can forward a port in the codespace settings.

If you set up Solargraph, you may also see port 7658 forwarded.

Give any feedback, suggestions, improvements, or issues you have about this to [@kunal](http://hackclub.slack.com/team/U013DC0KYC8) (kunal@hackclub.com).