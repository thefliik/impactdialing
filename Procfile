web:  bundle exec rails server thin -p $PORT 
dialer: bundle exec ruby lib/predictive_dialer.rb
resque_dialer: bundle exec ruby lib/resque_predictive_dialer.rb
new_simulator: bundle exec ruby simulator/newest_simulator.rb
email_worker_job: rake environment resque:work QUEUE=email_worker_job
voter_list_upload_worker_job: rake environment resque:work QUEUE=voter_list_upload_worker_job
report_download_worker_job: rake environment resque:work QUEUE=report_download_worker_job
monitor_worker: bundle exec ruby lib/monitor_tab_pusher.rb
dialer_worker: rake environment resque:work QUEUE=dialer_worker

