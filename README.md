# Five9-campaign-start-stop

Script uses Five9 Configuration Web Services API to start or stop multiple 
campaigns one after another listed in campaigns.txt file.

### How to run
1. set your Five9 username and password (Administrator role is required to make requests to Five9 API)
2. add campaigns to the campaigns.txt file or leave it blank to run for all campaigns
3. run main.pl perl file:
```
#> ./main.pl
```