create procedure syn.usp_ImportFileCustomerSeasonal
	@ID_Record int
-- 1. Все ключевые слова (в данном случае "as") пишутся в нижнем регистре
AS
set nocount on
begin
	-- 2. Следует использовать один раз "declare", а каждую переменную описывать с новой строки с отступом (через запятую)
	declare @RowCount int = (select count(*) from syn.SA_CustomerSeasonal)
	declare @ErrorMessage varchar(max)

-- Проверка на корректность загрузки
	-- 3. Комментарий выше должен быть с отступом как у кода на следующей строке
	if not exists (
	-- 4. Нижний блок кода "Select" также должен быть с отступом от уровня кода "if" 
	select 1
	-- 5. Алиас "f" не соответствует стандарту наименования алиаса, должно быть "imf"
	from syn.ImportFile as f
	where f.ID = @ID_Record
		and f.FlagLoaded = cast(1 as bit)
	)
		-- 6. Нижний блок "begin/end" должен быть на одном уровне с "if"
		begin
			set @ErrorMessage = 'Ошибка при загрузке файла, проверьте корректность данных'
			raiserror(@ErrorMessage, 3, 1)
			-- 7. Должна быть пустая строка перед "return"
			return
		end

	-- Чтение из слоя временных данных
	select
		c.ID as ID_dbo_Customer
		,cst.ID as ID_CustomerSystemType
		,s.ID as ID_Season
		,cast(cs.DateBegin as date) as DateBegin
		,cast(cs.DateEnd as date) as DateEnd
		,c_dist.ID as ID_dbo_CustomerDistributor
		,cast(isnull(cs.FlagActive, 0) as bit) as FlagActive
	into #CustomerSeasonal
	-- 8. Синтаксическая ошибка: нет "as" в следующем коде
	from syn.SA_CustomerSeasonal cs
		join dbo.Customer as c on c.UID_DS = cs.UID_DS_Customer
			and c.ID_mapping_DataSource = 1
		join dbo.Season as s on s.Name = cs.Season
		join dbo.Customer as c_dist on c_dist.UID_DS = cs.UID_DS_CustomerDistributor
			and c_dist.ID_mapping_DataSource = 1
		-- 9. В условии "on" ниже сперва указываем поле присоединяемой таблицы, то есть "cst.Name ="
		join syn.CustomerSystemType as cst on cs.CustomerSystemType = cst.Name
	where try_cast(cs.DateBegin as date) is not null
		and try_cast(cs.DateEnd as date) is not null
		and try_cast(isnull(cs.FlagActive, 0) as bit) is not null

	-- 10. Для комментариев в несколько строк используется конструкция  /* */ 
	-- Определяем некорректные записи
	-- Добавляем причину, по которой запись считается некорректной
	select
		cs.*
		,case
			-- 11. При написании конструкции с "case" необходимо, чтобы "when" был под "case" с 1 отступом, "then" - с 2 отступами
			when c.ID is null then 'UID клиента отсутствует в справочнике "Клиент"'
			when c_dist.ID is null then 'UID дистрибьютора отсутствует в справочнике "Клиент"'
			when s.ID is null then 'Сезон отсутствует в справочнике "Сезон"'
			when cst.ID is null then 'Тип клиента отсутствует в справочнике "Тип клиента"'
			when try_cast(cs.DateBegin as date) is null then 'Невозможно определить Дату начала'
			when try_cast(cs.DateEnd as date) is null then 'Невозможно определить Дату окончания'
			when try_cast(isnull(cs.FlagActive, 0) as bit) is null then 'Невозможно определить Активность'
		end as Reason
	into #BadInsertedRows
	from syn.SA_CustomerSeasonal as cs
	-- 12. Блок с "left join" ниже должен идти с отступом
	left join dbo.Customer as c on c.UID_DS = cs.UID_DS_Customer
		and c.ID_mapping_DataSource = 1
	-- 13. Если в "join" есть "and", то он переносится на следующую строку с отступом
	left join dbo.Customer as c_dist on c_dist.UID_DS = cs.UID_DS_CustomerDistributor and c_dist.ID_mapping_DataSource = 1
	left join dbo.Season as s on s.Name = cs.Season
	left join syn.CustomerSystemType as cst on cst.Name = cs.CustomerSystemType
	where c.ID is null
		or c_dist.ID is null
		or s.ID is null
		or cst.ID is null
		or try_cast(cs.DateBegin as date) is null
		or try_cast(cs.DateEnd as date) is null
		or try_cast(isnull(cs.FlagActive, 0) as bit) is null

	-- Обработка данных из файла
	/* 
		14. Перед названием таблицы, в которую осуществляется "merge", "into" не указывается
		15. Неверный алиас для таблицы, в которую осуществляется "merge" - он должен быть "t"
	*/
	merge into syn.CustomerSeasonal as cs
	using (
		select
			cs_temp.ID_dbo_Customer
			,cs_temp.ID_CustomerSystemType
			,cs_temp.ID_Season
			,cs_temp.DateBegin
			,cs_temp.DateEnd
			,cs_temp.ID_dbo_CustomerDistributor
			,cs_temp.FlagActive
		from #CustomerSeasonal as cs_temp
	) as s on s.ID_dbo_Customer = cs.ID_dbo_Customer
		and s.ID_Season = cs.ID_Season
		and s.DateBegin = cs.DateBegin
	-- 16. Все дополнительные условия остаются на строке с "when"
	when matched
		and t.ID_CustomerSystemType <> s.ID_CustomerSystemType then
		update
		-- 17. Обновляемые поля должны идти с новой строки
		set ID_CustomerSystemType = s.ID_CustomerSystemType
			,DateEnd = s.DateEnd
			,ID_dbo_CustomerDistributor = s.ID_dbo_CustomerDistributor
			,FlagActive = s.FlagActive
	when not matched then
		insert (ID_dbo_Customer, ID_CustomerSystemType, ID_Season, DateBegin, DateEnd, ID_dbo_CustomerDistributor, FlagActive)
		values (s.ID_dbo_Customer, s.ID_CustomerSystemType, s.ID_Season, s.DateBegin, s.DateEnd, s.ID_dbo_CustomerDistributor, s.FlagActive);

	-- Информационное сообщение
	begin
		select @ErrorMessage = concat('Обработано строк: ', @RowCount)
		raiserror(@ErrorMessage, 1, 1)

		-- 18. Между -- и самим комментарием должен быть пробел
		--Формирование таблицы для отчетности
		select top 100
			bir.Season as 'Сезон'
			,bir.UID_DS_Customer as 'UID Клиента'
			,bir.Customer as 'Клиент'
			,bir.CustomerSystemType as 'Тип клиента'
			,bir.UID_DS_CustomerDistributor as 'UID Дистрибьютора'
			,bir.CustomerDistributor as 'Дистрибьютор'
			,isnull(format(try_cast(bir.DateBegin as date), 'dd.MM.yyyy', 'ru-RU'), bir.DateBegin) as 'Дата начала'
			-- 19. Синтаксическая ошибка: нет точки между именем таблицы и именем поля
			,isnull(format(try_cast(birDateEnd as date), 'dd.MM.yyyy', 'ru-RU'), bir.DateEnd) as 'Дата окончания'
			,bir.FlagActive as 'Активность'
			,bir.Reason as 'Причина'
		from #BadInsertedRows as bir

		return
	end
end
