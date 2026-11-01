Table User {
 user_id bigint [pk]
 username varchar
 iphone Long [unique]
 email varchar [unique, not null]
 password varchar
 avator varchar
 status varchar
 createTime datetime
 birthday date
 updateTime datetime
 lastLoginTime datetime
 user_setting json
}

Table UserAsset {
 asset_id bigint [pk, increment]
 user_id bigint [unique]
 coin int [default: 0]
 exp bigint [default: 0]
 updateTime datetime [default: 'now()']
 water int [default: 0]
}

Table LevelConfig{
 //预存每一级升级需要的经验，**只读，不修改**
 level int [pk]
 requiredExp bigint

 badgeName varchar
 reward_coin int

 reward_water int

 badge_name varchar
}

Table Task {
 task_id bigint [pk]
 user_id bigint [ref: >User.user_id]

 title varchar
 note text

 start datetime
end datetime

target_count int [default: 1]
 status varchar

 importance int
 urgency int
 difficulty int

 priority_score decimal

 create_time datetime

 estimated_minutes int
}

Table Habit{
 habit_id bigint [pk]
 user_id bigint [ref: >User.user_id]
 name varchar

note text

start_date date

end_date date

repeat_rule json

status varchar
}

Table HabitRecord {

 habit_record_id bigint [pk, increment]

 habit_id bigint [ref: > Habit.habit_id]

 date date

 status varchar

 finish_time datetime

 actual_count int

}



Table ReminderSetting {
  setting_id bigint [pk, increment]
  user_id bigint [ref: > User.user_id]
  target_type varchar [not null]
  target_id bigint [not null]
  remind_time datetime [not null]
  enabled boolean [default: true]
}


Table AssetRecord {
  record_id bigint [pk]

 user_id bigint
  action varchar

 asset_type varchar

 amount int

 source varchar

 create_time datetime
}

Table TaskRecord {
  task_record_id bigint [pk, increment]
  task_id bigint [ref: > Task.task_id]
  date date
  status verchar
  finish_time datetime
  actual_count int
}


Table RewardConfig{
  reward_config_id bigint [pk]
  type verchar [unique]
  coin int
  exp int
  water int
}