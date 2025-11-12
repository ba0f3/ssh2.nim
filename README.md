# SSH2.nim

A high-level async SSH library for Nim, providing SSH, SCP, and SFTP functionality. Built on top of libssh2.

## Features

- ✨ Asynchronous API using `async`/`await`
- 🔒 Secure SSH connections with password and key authentication
- 📂 SCP file transfers (upload/download)
- 📁 SFTP operations (file transfer, directory management)
- 🛠️ Command execution on remote servers
- 🔐 Support for various authentication methods
- 📝 Comprehensive error handling

## Installation

1. First, ensure you have libssh2 installed on your system:

```bash
# Ubuntu/Debian
apt-get install libssh2-1-dev

# macOS
brew install libssh2

# Windows (using vcpkg)
vcpkg install libssh2:x64-windows
```

2. Install using Nimble:

```bash
nimble install ssh2
```

## Quick Start

```nim
import asyncdispatch
import ssh2

proc main() {.async.} =
  let ssh = newSSHClient()
  try:
    # Connect to remote server
    await ssh.connect("example.com", "username", password = "password")

    # Execute a command
    let (output, errorOutput, exitCode) = await ssh.execCommand("ls -la")
    echo "Command output: ", output

    # Upload a file using SCP
    let scp = initSCPClient(ssh)
    await scp.uploadFile("local.txt", "/remote/path/file.txt")

    # SFTP operations
    var sftp = initSFTPClient(ssh)
    defer: sftp.close()

    # Create directory
    sftp.mkdir("/remote/new_dir")

    # List directory contents
    let files = await sftp.dir("/remote/new_dir")
    for file in files:
    echo "File: ", file.name`
  finally:
    ssh.disconnect()

waitFor main()
```

## API Documentation

The library provides three main components:

### SSH Client
- Connect to remote servers
- Execute commands
- Handle authentication

### SCP Client
- Upload files
- Download files
- Preserve file permissions

### SFTP Client
- File transfers (upload/download)
- Directory operations (create, remove, list)
- File management (rename, delete)

For detailed API documentation, see the [documentation](https://nim-lang.org/docs/ssh2.html).

## Authentication Methods

The library supports multiple authentication methods:

```nim
# Password authentication
await ssh.connect("host", "user", password = "pass")

# Private key authentication
await ssh.connect("host", "user",
privateKeyPath = "~/.ssh/id_rsa",
passphrase = "optional-passphrase"
)

# Agent authentication
await ssh.connect("host", "user", useAgent = true)
```

## Error Handling

The library uses Nim's exception system for error handling:

```nim
try:
await ssh.connect("host", "user", password = "pass")
let (output, errorOutput, code) = await ssh.execCommand("command")
except SSHException as e:
echo "SSH error: ", e.msg
except IOError as e:
echo "IO error: ", e.msg
```

## Development

To run tests, you can use a Docker instance with sshd installed:

```bash
# Host: 127.0.0.1
# Port: 2222
# Username: root
# Password: root

docker run -d --name test_sshd -p 2222:22 rastasheep/ubuntu-sshd:16.04
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [libssh2](https://www.libssh2.org/) - The underlying SSH library
- [Nim](https://nim-lang.org/) - The programming language
