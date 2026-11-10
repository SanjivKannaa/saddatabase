mysql -e "alter user 'app'@'%' account unlock; alter user 'app'@'%' identified by 'S4fe-pass'; set default role billing_reader to 'app'@'%';"
