### CentOS

1. Get the files: ( [Zip](#) | [Tar.gz](#) )

    ```bash
    wget http://getkong.org/releases/kong-0.0.1-beta.tar.gz
    tar xvzf kong-0.0.1-beta.tar.gz
    ```

2. Install dependencies:

    ```bash
    wget http://luarocks.com
    ./configure && make && make install
    ```

2. Run:

    ```bash
    bin/kong migrate # Only the first time
    bin/kong start
    ```
