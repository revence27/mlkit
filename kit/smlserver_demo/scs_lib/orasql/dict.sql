-- All phrases gets its own number, phrase_id. One phase may 
-- be translated into several languages.
drop sequence scs_dict_phrase_seq;
create sequence scs_dict_phrase_seq start with 1;
drop table scs_dict_target;
drop table scs_dict_source;
create table scs_dict_source (
  phrase_id integer primary key,
  lang varchar(10) not null check (lang in ('English','Danish')),
  phrase varchar(3000) not null,
  script varchar(300) not null,
  entry_date date not null,
  -- for source phrases, we want all phrases within one language 
  -- to be unique
  unique (lang,phrase));

drop sequence scs_dict_target_seq;
create sequence scs_dict_target_seq start with 1;
create table scs_dict_target (
  target_id integer primary key,
  phrase_id integer references scs_dict_source on delete cascade not null ,
  lang varchar(10) not null check (lang in ('English','Danish')),
  phrase varchar(3000) not null,
  -- we don't want lang and phrase to be unique as different source 
  -- phrases may translate into the same target phrase; however 
  -- phrase_id and lang must be unique
  unique (phrase_id,lang));

-- Necessary for the email-example
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (1,1,'English','Type your email');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (4,1,'Danish','Indtast din mail');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (2,2,'English','Type subject');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (5,2,'Danish','Indtast emne');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (3,3,'English','Type body');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (6,3,'Danish','Indtast besked');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (7,4,'English','Send Message');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (8,4,'Danish','Send Besked');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (9,5,'English','Logout');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (10,5,'Danish','Log Ud');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (11,6,'English','authentication example');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (12,6,'Danish','valideringseksemplet');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (13,7,'English','SMLserver Home Page');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (14,7,'Danish','SMLserver Start Side');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (15,8,'English','"Email Sent"');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (16,8,'Danish','Email Sendt');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (17,9,'English','Your email has been sent');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (18,9,'Danish','Din email er sendt');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (19,10,'English','Thank You');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (20,10,'Danish','Mange Tak');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (21,11,'English','Show Cookies');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (22,11,'Danish','Vis Cookies');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (23,12,'English','page');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (24,12,'Danish','siden');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (25,13,'English','Back to');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (26,13,'Danish','Tilbage til');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (27,14,'English','Error in field');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (28,14,'Danish','Fejl i indtastningsfelt');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (29,15,'English','You must provide a');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (30,15,'Danish','Du skal indstaste');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (31,16,'English','is not a');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (32,16,'Danish','er ikke');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (33,17,'English','More than one dataitem is provided');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (34,17,'Danish','Du har angivet mere et end en v�rdi');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (35,18,'English','Form Error');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (36,18,'Danish','Fejl i de indtastede data');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (37,19,'English','number');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (38,19,'Danish','nummer');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (39,20,'English','positive number');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (40,20,'Danish','positivt nummer');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (41,21,'English','real');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (42,21,'Danish','kommatal');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (43,23,'English','The integer');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (44,23,'Danish','Heltallet');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (45,24,'English','is not within the valid range');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (46,24,'Danish','er uden for det tilladte interval');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (47,25,'English','You must provide an valid');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (48,25,'Danish','Du skal indtaste korrekt');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (49,26,'English','is not one');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (50,26,'Danish','er ikke');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (51,27,'English','email');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (52,27,'Danish','email');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (53,28,'English','name');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (54,28,'Danish','navn');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (55,29,'English','address');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (56,29,'Danish','adresse');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (57,30,'English','login');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (58,30,'Danish','login');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (59,31,'English','phone number');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (60,31,'Danish','telefonnummer');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (61,32,'English','HTML text');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (62,32,'Danish','HTML dokument');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (63,33,'English','URL');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (64,33,'Danish','URL');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (65,34,'English','cpr number');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (66,34,'Danish','cpr nummer');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (67,35,'English','enumeration');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (68,35,'Danish','valgliste');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (69,36,'English','date');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (70,36,'Danish','dato');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (71,22,'English','string');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (72,22,'Danish','tegnstreng');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (73,37,'English','Yes/No');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (74,37,'Danish','Ja/Nej');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (75,38,'English','Yes');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (76,38,'Danish','Ja');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (77,39,'English','No');
-- insert into scs_dict (dict_id, phrase_id, lang, text) values (78,39,'Danish','Nej');

commit;
column text format a30;