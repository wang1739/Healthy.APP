CREATE TABLE foods (
  id VARCHAR(36) PRIMARY KEY,
  owner_user_id VARCHAR(36),
  name VARCHAR(30) NOT NULL,
  system_name VARCHAR(30) GENERATED ALWAYS AS
    (CASE WHEN owner_user_id IS NULL THEN name ELSE NULL END),
  category VARCHAR(24) NOT NULL,
  calories_per_100g DECIMAL(8,2) NOT NULL,
  protein_per_100g DECIMAL(7,2) NOT NULL,
  carbs_per_100g DECIMAL(7,2) NOT NULL,
  fat_per_100g DECIMAL(7,2) NOT NULL,
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  deleted_at TIMESTAMP(6),
  CONSTRAINT fk_food_owner FOREIGN KEY (owner_user_id) REFERENCES users(id),
  CONSTRAINT uk_food_owner_name UNIQUE (owner_user_id, name),
  CONSTRAINT uk_system_food_name UNIQUE (system_name),
  CONSTRAINT ck_food_calories CHECK (calories_per_100g >= 0 AND calories_per_100g <= 900),
  CONSTRAINT ck_food_protein CHECK (protein_per_100g >= 0 AND protein_per_100g <= 100),
  CONSTRAINT ck_food_carbs CHECK (carbs_per_100g >= 0 AND carbs_per_100g <= 100),
  CONSTRAINT ck_food_fat CHECK (fat_per_100g >= 0 AND fat_per_100g <= 100)
);

CREATE INDEX idx_food_name ON foods(name);
CREATE INDEX idx_food_owner ON foods(owner_user_id, deleted_at);

CREATE TABLE food_portions (
  id VARCHAR(36) PRIMARY KEY,
  food_id VARCHAR(36) NOT NULL,
  label VARCHAR(30) NOT NULL,
  grams DECIMAL(8,2) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  CONSTRAINT fk_portion_food FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE CASCADE,
  CONSTRAINT uk_portion_food_label UNIQUE (food_id, label),
  CONSTRAINT ck_portion_grams CHECK (grams > 0 AND grams <= 5000)
);

CREATE INDEX idx_portion_food_sort ON food_portions(food_id, sort_order, id);

CREATE TABLE meal_entries (
  id VARCHAR(36) PRIMARY KEY,
  user_id VARCHAR(36) NOT NULL,
  entry_date DATE NOT NULL,
  meal_type VARCHAR(16) NOT NULL,
  food_id VARCHAR(36),
  food_name_snapshot VARCHAR(30) NOT NULL,
  grams DECIMAL(8,2) NOT NULL,
  calories_snapshot DECIMAL(10,4) NOT NULL,
  protein_snapshot DECIMAL(10,4) NOT NULL,
  carbs_snapshot DECIMAL(10,4) NOT NULL,
  fat_snapshot DECIMAL(10,4) NOT NULL,
  idempotency_key VARCHAR(100),
  created_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  deleted_at TIMESTAMP(6),
  CONSTRAINT fk_meal_user FOREIGN KEY (user_id) REFERENCES users(id),
  CONSTRAINT fk_meal_food FOREIGN KEY (food_id) REFERENCES foods(id),
  CONSTRAINT uk_meal_idempotency UNIQUE (user_id, idempotency_key),
  CONSTRAINT ck_meal_type CHECK (meal_type IN ('BREAKFAST','LUNCH','DINNER','SNACK')),
  CONSTRAINT ck_meal_grams CHECK (grams > 0 AND grams <= 5000),
  CONSTRAINT ck_meal_calories CHECK (calories_snapshot >= 0 AND calories_snapshot <= 45000),
  CONSTRAINT ck_meal_protein CHECK (protein_snapshot >= 0 AND protein_snapshot <= 5000),
  CONSTRAINT ck_meal_carbs CHECK (carbs_snapshot >= 0 AND carbs_snapshot <= 5000),
  CONSTRAINT ck_meal_fat CHECK (fat_snapshot >= 0 AND fat_snapshot <= 5000)
);

CREATE INDEX idx_meal_user_date ON meal_entries(user_id, entry_date, deleted_at, meal_type, created_at);
CREATE INDEX idx_meal_food_history ON meal_entries(user_id, food_id, deleted_at, created_at);

INSERT INTO foods
(id, owner_user_id, name, category, calories_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g) VALUES
('sys-rice',NULL,'米饭','STAPLE',116,2.6,25.9,0.3),
('sys-congee',NULL,'白粥','STAPLE',46,1.1,9.9,0.3),
('sys-noodle',NULL,'煮面条','STAPLE',110,2.7,23.5,0.2),
('sys-steamed-bun',NULL,'馒头','STAPLE',223,7.0,47.0,1.1),
('sys-whole-wheat',NULL,'全麦面包','STAPLE',246,9.9,46.0,3.4),
('sys-oats',NULL,'燕麦片','STAPLE',338,10.1,77.4,0.2),
('sys-sweet-potato',NULL,'红薯','STAPLE',86,1.6,20.1,0.1),
('sys-corn',NULL,'玉米','STAPLE',112,4.0,22.8,1.2),
('sys-potato',NULL,'土豆','STAPLE',77,2.0,17.5,0.1),
('sys-chicken-breast',NULL,'鸡胸肉','MEAT',133,24.6,2.5,2.0),
('sys-chicken-leg',NULL,'鸡腿肉','MEAT',181,16.0,0,13.0),
('sys-lean-pork',NULL,'瘦猪肉','MEAT',143,20.3,1.5,6.2),
('sys-beef',NULL,'瘦牛肉','MEAT',106,20.2,1.2,2.3),
('sys-salmon',NULL,'三文鱼','MEAT',139,17.2,0,7.8),
('sys-shrimp',NULL,'虾仁','MEAT',93,18.6,2.8,0.8),
('sys-egg',NULL,'鸡蛋','PROTEIN',144,13.3,2.8,8.8),
('sys-milk',NULL,'纯牛奶','DAIRY',54,3.0,3.4,3.2),
('sys-yogurt',NULL,'原味酸奶','DAIRY',72,2.5,9.3,2.7),
('sys-tofu',NULL,'北豆腐','PROTEIN',116,12.2,4.8,6.5),
('sys-soy-milk',NULL,'无糖豆浆','PROTEIN',31,3.0,1.2,1.6),
('sys-broccoli',NULL,'西兰花','VEGETABLE',36,4.1,4.3,0.6),
('sys-spinach',NULL,'菠菜','VEGETABLE',28,2.6,4.5,0.3),
('sys-cabbage',NULL,'大白菜','VEGETABLE',20,1.6,3.4,0.2),
('sys-tomato',NULL,'西红柿','VEGETABLE',15,0.9,3.3,0.2),
('sys-cucumber',NULL,'黄瓜','VEGETABLE',16,0.8,2.9,0.2),
('sys-carrot',NULL,'胡萝卜','VEGETABLE',32,1.0,7.7,0.2),
('sys-mushroom',NULL,'香菇','VEGETABLE',26,2.2,5.2,0.3),
('sys-lettuce',NULL,'生菜','VEGETABLE',16,1.3,2.1,0.4),
('sys-apple',NULL,'苹果','FRUIT',53,0.4,13.7,0.2),
('sys-banana',NULL,'香蕉','FRUIT',93,1.4,22.0,0.2),
('sys-orange',NULL,'橙子','FRUIT',48,0.8,11.1,0.2),
('sys-pear',NULL,'梨','FRUIT',51,0.3,13.1,0.1),
('sys-grape',NULL,'葡萄','FRUIT',45,0.4,10.3,0.3),
('sys-watermelon',NULL,'西瓜','FRUIT',31,0.6,6.8,0.1),
('sys-strawberry',NULL,'草莓','FRUIT',32,1.0,7.1,0.2),
('sys-blueberry',NULL,'蓝莓','FRUIT',57,0.7,14.5,0.3),
('sys-almond',NULL,'杏仁','SNACK',578,22.5,23.9,45.4),
('sys-walnut',NULL,'核桃','SNACK',646,14.9,19.1,58.8),
('sys-peanut',NULL,'花生','SNACK',567,24.8,21.7,48.0),
('sys-dark-chocolate',NULL,'黑巧克力','SNACK',589,7.8,45.9,42.6);

INSERT INTO food_portions (id, food_id, label, grams, sort_order) VALUES
('portion-rice-1','sys-rice','1 碗',150,1),('portion-congee-1','sys-congee','1 碗',250,1),
('portion-noodle-1','sys-noodle','1 碗',200,1),('portion-bun-1','sys-steamed-bun','1 个',80,1),
('portion-bread-1','sys-whole-wheat','1 片',30,1),('portion-oats-1','sys-oats','1 份',40,1),
('portion-sweet-potato-1','sys-sweet-potato','1 个',150,1),('portion-corn-1','sys-corn','1 根',200,1),
('portion-potato-1','sys-potato','1 个',150,1),('portion-chicken-breast-1','sys-chicken-breast','1 份',150,1),
('portion-chicken-leg-1','sys-chicken-leg','1 个',120,1),('portion-pork-1','sys-lean-pork','1 份',100,1),
('portion-beef-1','sys-beef','1 份',100,1),('portion-salmon-1','sys-salmon','1 份',100,1),
('portion-shrimp-1','sys-shrimp','1 份',100,1),('portion-egg-1','sys-egg','1 个',50,1),
('portion-milk-1','sys-milk','1 杯',250,1),('portion-yogurt-1','sys-yogurt','1 杯',150,1),
('portion-tofu-1','sys-tofu','1 份',100,1),('portion-soy-milk-1','sys-soy-milk','1 杯',250,1),
('portion-broccoli-1','sys-broccoli','1 份',150,1),('portion-spinach-1','sys-spinach','1 份',150,1),
('portion-cabbage-1','sys-cabbage','1 份',200,1),('portion-tomato-1','sys-tomato','1 个',150,1),
('portion-cucumber-1','sys-cucumber','1 根',200,1),('portion-carrot-1','sys-carrot','1 根',100,1),
('portion-mushroom-1','sys-mushroom','1 份',100,1),('portion-lettuce-1','sys-lettuce','1 份',150,1),
('portion-apple-1','sys-apple','1 个',200,1),('portion-banana-1','sys-banana','1 根',120,1),
('portion-orange-1','sys-orange','1 个',180,1),('portion-pear-1','sys-pear','1 个',200,1),
('portion-grape-1','sys-grape','1 份',150,1),('portion-watermelon-1','sys-watermelon','1 块',300,1),
('portion-strawberry-1','sys-strawberry','1 份',150,1),('portion-blueberry-1','sys-blueberry','1 份',100,1),
('portion-almond-1','sys-almond','1 小把',20,1),('portion-walnut-1','sys-walnut','1 小把',20,1),
('portion-peanut-1','sys-peanut','1 小把',20,1),('portion-chocolate-1','sys-dark-chocolate','1 小块',10,1);
