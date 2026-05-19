## Oracle XE on Apple M chips

Currently, there is no Oracle Database port for ARM chips, hence Oracle XE Images cannot run on the new Apple M chips
via Docker Desktop.
Fortunately, there are other technologies that can spin up x86_64 software on Apple M chips, such as colima .
To run these Oracle XE images on Apple M hareware, follow these simple steps:

1. Install colima: https://github.com/abiosoft/colima
2. Start colima: colima start --arch x86_64 --memory 4
3. Start container as usual
