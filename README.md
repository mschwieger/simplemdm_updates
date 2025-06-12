# SimpleMDM Management Script

A Bash script to automate actions with SimpleMDM device and assignment groups, featuring healthchecks.io monitoring and optional Postmark log email.

## Features

- Randomized execution window for cron jobs (8am/8pm, random start, min 4 hours apart)
- Full logging to healthchecks.io and email (Postmark)
- .env-based configuration (no secrets in the repo)
- MIT licensed (see header in script)

## Quick Start

1. **Clone the repo**
    ```bash
    git clone https://github.com/youruser/simplemdm-script.git
    cd simplemdm-script
    ```

2. **Prepare your configuration**

    Copy the example environment file and fill in your values:

    ```bash
    cp .env.example .env
    nano .env
    ```

    Fill in your API keys and email addresses as needed.

3. **Make the script executable**

    ```bash
    chmod +x simplemdm-script.sh
    ```

4. **Test it**

    Run with no arguments for production behavior (random sleep), or with `--nosleep` for immediate execution (useful for testing):

    ```bash
    ./simplemdm-script.sh --nosleep
    ```

5. **Automate with cron (optional)**

    To run at 8am and 8pm each day (with randomized start within the next 4 hours):

    ```bash
    crontab -e
    ```

    Add this line:

    ```
    0 8,20 * * * /path/to/simplemdm-script/simplemdm-script.sh
    ```

## Environment File (`.env`)

Configuration is loaded from a `.env` file in the script directory. Example:

```env
API_KEY=your_simplemdm_api_key
HEALTHCHECKS_URL=https://hc-ping.com/your-uuid-here
POSTMARK_API_KEY=your_postmark_api_token
POSTMARK_FROM=from@example.com
POSTMARK_TO=to@example.com
POSTMARK_SUBJECT=SimpleMDM Script Output
