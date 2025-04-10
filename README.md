# generate

A Bash script that generates password strings, JWT tokens and API keys.

## Versions

**Current version**: 0.2.0

## Table of Contents

- [Versions](#versions)
- [Badges](#badges)
- [Installation](#installation)
- [Usage](#usage)
- [License](#license)
- [Contributing](#contributing)

## Badges

![Bash](https://img.shields.io/badge/language-Bash-blue)
![Version](https://img.shields.io/badge/version-0.2.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Installation

1. Clone the repository: `git clonehttps://github.com/beecave-homelab/generate.git`
2. Navigate to the directory: `cd generate`
3. Make the script executable: `chmod +x generate.sh`
4. Optionally, copy the script into the `/usr/local/bin/` directory:  `sudo cp generate.sh /usr/local/bin/generate`

## Usage

Run the script with one of the following commands:

- `./generate.sh pass [OPTIONS]` to generate a passphrase.
- `./generate.sh tkn` to generate a JWT-like token.
- `./generate.sh api [OPTIONS]` to generate an API token.

Use the `-h` or `--help` flag for more detailed usage instructions.

## License

This project is licensed under the MIT license. See [LICENSE](LICENSE) for more information.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.
