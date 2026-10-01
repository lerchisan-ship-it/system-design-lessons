# Benchmark PostgreSQL — контрольная точка на 1 000 пользователей

Дата фиксации: **30 сентября 2026**

## 1. Размер тестового набора данных

| Таблица | Количество строк |
|---|---:|
| `users` | 1 000 |
| `profiles` | 1 000 |
| `cars` | 100 |
| `rentals` | 1 700 |
| `accidents` | 110 |

Доля ДТП среди аренд: **6,47%**.

Для каждого benchmark-запроса использовался:

```sql
EXPLAIN (ANALYZE, BUFFERS)
```

Каждый запрос запускался **3 раза**. В итоговой таблице используется **медиана `Execution Time`**.

---

# 2. Benchmark-запросы и результаты

## Тест 1. Поиск пользователя по email

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    u.user_id,
    u.email,
    p.full_name,
    p.driver_license
FROM users AS u
JOIN profiles AS p
    ON p.user_id = u.user_id
WHERE u.email = 'loadtest_user_0999@example.invalid';
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,040 мс |
| 2 | 0,033 мс |
| 3 | 0,033 мс |
| **Медиана** | **0,033 мс** |

Наблюдение: PostgreSQL использовал индексный поиск по `users.email` и связанный индекс по `profiles.user_id`.

---

## Тест 2. `COUNT(*)` по таблице `users`

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM users;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,106 мс |
| 2 | 0,077 мс |
| 3 | 0,154 мс |
| **Медиана** | **0,106 мс** |

Наблюдение: на 1 000 строк PostgreSQL использовал обычный `Seq Scan`.

---

## Тест 3. История одного пользователя

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    r.rental_id,
    r.car_id,
    r.started_at,
    r.ended_at,
    r.rating_at_start,
    r.total_cost
FROM users AS u
JOIN profiles AS p
    ON p.user_id = u.user_id
JOIN rentals AS r
    ON r.profile_id = p.profile_id
WHERE u.email = 'loadtest_user_0999@example.invalid'
ORDER BY r.started_at;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,141 мс |
| 2 | 0,049 мс |
| 3 | 0,047 мс |
| **Медиана** | **0,049 мс** |

Наблюдение: PostgreSQL использовал индексные переходы по цепочке `users → profiles → rentals`.

---

## Тест 4. История одной машины + ДТП

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.registration_number,
    r.rental_id,
    r.started_at,
    r.ended_at,
    a.accident_id,
    a.occurred_at,
    a.user_guilty
FROM cars AS c
JOIN rentals AS r
    ON r.car_id = c.car_id
LEFT JOIN accidents AS a
    ON a.rental_id = r.rental_id
WHERE c.registration_number = 'LOADCAR-000001'
ORDER BY r.started_at;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,221 мс |
| 2 | 0,157 мс |
| 3 | 0,198 мс |
| **Медиана** | **0,198 мс** |

Наблюдение: на маленькой таблице `cars` PostgreSQL мог предпочесть последовательный просмотр 100 строк, а для `accidents` использовал индекс по `rental_id`.

---

## Тест 5. Поиск аренд с `rating_at_start = 95`

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM rentals
WHERE rating_at_start = 95;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,134 мс |
| 2 | 0,115 мс |
| 3 | 0,094 мс |
| **Медиана** | **0,115 мс** |

Наблюдение: отдельного индекса по `rating_at_start` нет, поэтому использовался `Seq Scan`. На 1 700 строк это всё ещё очень дешёвая операция.

---

## Тест 6. Топ аварийных машин

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.registration_number,
    COUNT(a.accident_id) AS accidents_count
FROM cars AS c
JOIN rentals AS r
    ON r.car_id = c.car_id
JOIN accidents AS a
    ON a.rental_id = r.rental_id
GROUP BY
    c.car_id,
    c.registration_number
ORDER BY accidents_count DESC
LIMIT 20;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 4,320 мс |
| 2 | 0,290 мс |
| 3 | 0,220 мс |
| **Медиана** | **0,290 мс** |

Наблюдение: первый запуск заметно выбился вверх; для итогового сравнения используется медиана. На этом объёме PostgreSQL использовал последовательные просмотры маленьких таблиц и hash-операции.

---

## Тест 7. Выручка по маркам автомобилей

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.brand,
    COUNT(r.rental_id) AS rentals_count,
    ROUND(SUM(r.total_cost), 2) AS total_revenue,
    ROUND(AVG(r.total_cost), 2) AS avg_rental_cost
FROM cars AS c
JOIN rentals AS r
    ON r.car_id = c.car_id
GROUP BY c.brand
ORDER BY total_revenue DESC;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,574 мс |
| 2 | 0,516 мс |
| 3 | 0,569 мс |
| **Медиана** | **0,569 мс** |

Наблюдение: использовались `Seq Scan` по `rentals` и `cars`, затем hash join и агрегирование по небольшому числу марок.

---

## Тест 8. Топ клиентов по количеству аренд и затратам

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    r.profile_id,
    COUNT(*) AS rentals_count,
    SUM(r.total_cost) AS total_spent
FROM rentals AS r
GROUP BY r.profile_id
ORDER BY
    rentals_count DESC,
    total_spent DESC
LIMIT 20;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,682 мс |
| 2 | 0,669 мс |
| 3 | 0,722 мс |
| **Медиана** | **0,682 мс** |

Наблюдение: использовался `HashAggregate`. На 1 000 групп агрегация полностью помещалась в памяти (`Batches: 1`, около 625 kB).

---

## Тест 9. Фильтр по `started_at` без отдельного ведущего индекса

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM rentals
WHERE started_at >= TIMESTAMPTZ '2025-03-01 00:00:00+03'
  AND started_at <  TIMESTAMPTZ '2025-04-01 00:00:00+03';
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,134 мс |
| 2 | 0,126 мс |
| 3 | 0,119 мс |
| **Медиана** | **0,126 мс** |

Наблюдение: использовался `Seq Scan` по `rentals`. Составной индекс `(profile_id, started_at)` не является подходящим ведущим индексом для фильтрации только по `started_at`.

---

## Тест 10. TOP-20 самых дорогих аренд

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    rental_id,
    profile_id,
    total_cost
FROM rentals
ORDER BY total_cost DESC
LIMIT 20;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,345 мс |
| 2 | 0,272 мс |
| 3 | 0,280 мс |
| **Медиана** | **0,280 мс** |

Наблюдение: использовался `Seq Scan`, затем `top-N heapsort`. Сортировка занимала около 27 kB памяти.

---

# 3. Итоговая таблица — 1 000 пользователей

| № | Тест | Медиана Execution Time |
|---:|---|---:|
| 1 | Пользователь по email | **0,033 мс** |
| 2 | `COUNT(*) users` | **0,106 мс** |
| 3 | История пользователя | **0,049 мс** |
| 4 | История машины + ДТП | **0,198 мс** |
| 5 | `rating_at_start = 95` | **0,115 мс** |
| 6 | Топ аварийных машин | **0,290 мс** |
| 7 | Выручка по маркам | **0,569 мс** |
| 8 | Топ клиентов по арендам | **0,682 мс** |
| 9 | Фильтр по `started_at` | **0,126 мс** |
| 10 | TOP-20 по `total_cost` | **0,280 мс** |

---

# 4. Краткий вывод по контрольной точке 1k

На объёме в 1 000 пользователей и 1 700 аренд все протестированные запросы выполняются очень быстро — медианные значения находятся в пределах от **0,033 мс** до **0,682 мс**.

На этом масштабе PostgreSQL часто предпочитает обычный `Seq Scan`, поскольку полный просмотр маленькой таблицы дешевле дополнительных обращений к индексу. Индексы уже используются для точечных поисков и связей, но наиболее интересные изменения планов ожидаются на следующих этапах: **10k, 100k и 1M пользователей**.
