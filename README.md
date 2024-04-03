# runboot
`runboot` is a PowerShell script designed to automate the setup of a new Windows development environment, optimized for Unreal Engine development. It simplifies the process of installing various dependencies and tools, including Visual Studio and more, using the [winget](https://docs.microsoft.com/en-us/windows/package-manager/winget/) package manager. It is optimized to run on Windows Server 2022 to configure a CI/CD environment but can be easily customized.

There is experimental work in progress to use [Deno](https://github.com/denoland/deno) and TypeScript instead of PowerShell - a sort of [CDK](https://docs.aws.amazon.com/cdk/latest/guide/what-is.html) for Windows setup.

## Features

- **winget Integration**: Automates the installation of tools and dependencies using the winget package manager.
- **Customizable**: Supports a configurable list of dependencies from a JSON file, allowing for easy customization of the development environment.
- **Comprehensive**: Installs essential tools for Unreal Engine development, including Visual Studio 2022, Visual Studio Code, and the Epic Games Launcher.

## Getting Started

### Prerequisites

- Windows 11 or Windows Server 2022 (older versions may work but are untested).
- Administrator privileges on your system.
- [winget](https://docs.microsoft.com/en-us/windows/package-manager/winget/) installed (the script can install winget if it's not already present).

### Installation

1. Clone the repository or download the `runboot.ps1` script directly.
```shell
git clone https://github.com/runreal/runboot.git
```

2. Open PowerShell as an Administrator.
3. Navigate to the directory containing `runboot.ps1`.
4. Execute the script with the desired parameters. For example, to install all components:
```powershell
.\runboot.ps1 -All
```

## Usage

RunBoot supports several command-line options to customize the installation process:

- `-Winget`: Install the winget package manager.
- `-Deps`: Install dependencies listed in the `winget-packages.json` file.
- `-Vs`: Install Visual Studio 2022 and Visual Studio Code.
- `-Buildkite`: Install the Buildkite agent.
- `-SevenZip`: Install 7-Zip and add to PATH.
- `-All`: Install all components. This is the default if no options are specified.
- `-Help`: Displays help information about the script.

For detailed information on each parameter, run:
```powershell
.\runboot.ps1 -Help
```

## Customizing Dependencies

The `winget-packages.json` file contains a list of packages to install. You can modify this file to add, remove, or modify the installed packages. `winget` install is idempotent so you can run the script multiple times without causing any issues.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues to improve the script or add new features.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

`winget` installation is based on the work of [asheroto](https://github.com/asheroto/winget-install).

