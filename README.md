# qb-vehiclesales
Used Car Sale for QB-Core Framework :blue_car:

## Dependencies
- [qb-core](https://github.com/Qbox-project/qb-core)
- [qb-garages](https://github.com/Qbox-project/qb-garages) - Vehicle ownership
- [qb-phone](https://github.com/Qbox-project/qb-phone) - For the e-mail
- [qb-logs](https://github.com/Qbox-project/qb-logs) - Keep event logs

## Screenshots
![Put Vehicle On Sale](https://imgur.com/bzE9e3o.png)
![Vehicle Sale Contract](https://imgur.com/A1ARcFV.png)
![Sell Vehicle To Dealer](https://imgur.com/zpEeBwk.png)
![Vehicle Sold Mail](https://imgur.com/vvz2UM3.png)
![Buy Vehicle](https://imgur.com/BEf5nDu.png)
![Vehicle Actions](https://imgur.com/HMuXtBd.png)

## Features
- Ability to put your vehicle on sale for other players to buy
- Ability to take your vehicle back if it is not sold yet
- Ability to sell your vehicle to the dealer for a fixed amount

## Installation
### Manual
- Download the script and put it in the `[qb]` directory.
- Import `qb-vehiclesales.sql` in your database
- Add the following code to your server.cfg/resouces.cfg
```
ensure qb-core
ensure qb-garages
ensure qb-phone
ensure qb-logs
ensure qb-vehiclesales
```