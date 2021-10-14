
use DBPROGRAM
go
-----------------------------------------------------------------------------------------------
print 'procedure cl_dbo_Migra_Plano_Cadastro_DAO				Versão: '+CONVERT( VARCHAR(10), getdate(), 103 )
-----------------------------------------------------------------------------------------------
if exists (select * from sysobjects where id = object_id('cl_dbo_Migra_Plano_Cadastro_DAO') and sysstat & 0xf = 4)
	drop procedure cl_dbo_Migra_Plano_Cadastro_DAO
go

create procedure cl_dbo_Migra_Plano_Cadastro_DAO
	@p_NroInscricao 		int 		= null
,	@p_SeqCliente 			smallint 	= Null
,	@p_NroPlano			smallint 	= null
,	@p_TipoOperacao			tinyint		= null	-- 0: Migração de Plano, 1: Retorno com Migração de Plano
,	@p_TipoRetorno			tinyint		= null	-- 1: Reingresso, 3: Regularização, 5: Decisão Judicial, 7: Adesão
,	@p_StaGeraProRataAutomatico	tinyint		= 1	-- status para indicar geração automática ou não de pró-rata
,	@p_StaDisableCheck		tinyint		= 0	--define que a migração poderá ser efetuada diretamente sem passar por críticas. Usado inicialmente para alterações em batch

,	@p_StaMigracaoAutomatica	tinyint		= 0	--define se a migração está sendo feita em batch ou não
,	@p_NroSitMigracaoAutomatica	tinyint		= 0	--define status da migração automática	--0: edição, 1: efetuada, 5: validação, 9: cancelada
,	@p_MsgOutput			varchar(2048)	= ''	output
,	@p_DisableRaiserror		tinyint		= 0	--define se a função raiserror será ou não executada
,	@p_StaSomenteValidacao		tinyint		= 0	-- define se haverá somente validação das regras ou efetuará o retorno por completo

,	@p_UserId	 numeric(11,0)
,	@p_Operacao			char(1)		= null
,	@p_NmeUsuario			varchar(32)	= null
,	@p_Option			tinyint		= 0
as
/*
	@p_TipoOperacao: descreve o tipo de operação que está sendo executada no cadastro de clientes:
		- 0: Migração de Plano
		- 1: Retorno com Migração de Plano

*/
set nocount on

-- ** verifica parâmetro(s) obrigatório(s) **
if ( @p_NroInscricao is null or ( @p_Operacao = 'E' and ( @p_NroPlano is null or @p_SeqCliente is null ) ) ) begin
	raiserror( 'Parâmetros insuficientes para a operação solicitada', 10,  1 )
	return 50000
end


-- ** declaração de variáveis **
declare @Retorno			int
,	@Erro				int


if ( @p_Operacao = 'E' ) begin

	-- ** declaração de variáveis **
	declare @Date 					datetime
	,	@NroUa					smallint
	,	@MsgOutput				varchar(2048)
	,	@MsgWarning				varchar(1024)
	,	@MsgReturn				varchar(2560)
	--,	@NroObs					tinyint
	,	@MsgError				varchar(1024)
	,	@StartedTransaction			smallint
	,	@ProcessoEspecialLiminar		BIT		= 0	--super usuário

	-- ** D030 **
	,	@D030NmeMae				char(70)
	,	@D030NroCpfCliente			numeric(11,0)
	
	-- ** PS71 **
	,	@PS71StaAgregado			tinyint
	
	--portabilidde
	,	@NroPortabilidadeCarencia		int
	,	@SolicitacaoPortabilidadeDeferidaComPrazoAindaValido	tinyint	= 0

	
	-- ** inicializa variáveis **
	--set @Erro					= 0
	set @Date 					= getdate()
	set @MsgOutput					= ''
	set @MsgWarning					= ''
	set @MsgReturn 					= ''
	set @MsgError					= ''
	set @StartedTransaction				= XACT_STATE()
	set @p_TipoRetorno				= iif( @p_TipoRetorno is null, 3, @p_TipoRetorno )	--3: Regularização
	set @p_TipoOperacao				= iif( @p_TipoRetorno = 3, 0, 1 )
	


	-- ** ======================================================================================================================
	-- ** RECUPERA VALORES **
	-- ** ======================================================================================================================
	
	-- ** recupera variáveis necessárias para críticas/atualizações **
	SELECT	@D030NmeMae								= x.NmeMae
	,	@D030NroCpfCliente							= x.NroCpfCliente
	,	@PS71StaAgregado							= x.StaAgregado
	from	DBPROGRAM.dbo.cl_fnc_InformacoesBasicasCliente( @p_NroInscricao, @p_SeqCliente, null, 0 ) as x
	
	-- ** regra nº. 380 **
	-- ** O retorno de um beneficiário em decorrência de uma liminar judicial seja na mesma inscrição **
	-- ** ou numa nova inscrição – manutenção – requer a existência de um objeto liminar cadastrado e **
	-- ** que o tipo de retorno seja “Decisão Judicial”. Caso não exista liminar, exibir mensagem: **
	-- ** “OBJETO LIMINAR NÃO CADASTRADO”. O retorno por liminar judicial deverá se sobrepor a qualquer **
	-- ** outra regra que o impeça de ser efetivado. No caso de retorno noutra inscrição, as informações **
	-- ** da liminar, cadastradas na inscrição anterior, deverão ser copiadas para a nova também **
	EXECUTE	@ProcessoEspecialLiminar = DBPROGRAM.dbo.cl_fnc_RetornoDevidoLiminar @p_NroInscricao, 0, 3--@p_TipoRetorno

	
	--recupera informações de portabilidade
	select	@NroPortabilidadeCarencia						= x.NroPortabilidadeCarencia
	from	CADASTRO_CLIENTE.dbo.CL61_PORTABILIDADE_CARENCIA			as x
		inner join CADASTRO_CLIENTE.dbo.CL62_SOLICITANTE_PORTABILIDADE_CARENCIA as y
			on y.NroPortabilidadeCarencia = x.NroPortabilidadeCarencia
	where	y.NroCpfCliente								= @D030NroCpfCliente
	--0:pendente, 1:deferido, 2:indeferido, 3:cancelado
	and	x.NroSituacao								= 1
	and	x.DtaSolicitacao							> dateadd( day, -10, getdate() )
	if @NroPortabilidadeCarencia is not null begin	
		select	@SolicitacaoPortabilidadeDeferidaComPrazoAindaValido		= DBPROGRAM.dbo.cl_fnc_SolicitacaoPortabilidadeDeferidaComPrazoAindaValido( @NroPortabilidadeCarencia )
		if @SolicitacaoPortabilidadeDeferidaComPrazoAindaValido is null		set @SolicitacaoPortabilidadeDeferidaComPrazoAindaValido = 0
	end

	
	-- ============================================================		
	-- ** REGRAS DE NEGÓCIO **
	-- ============================================================
	execute @Retorno			= dbo.cl_chk_Migra_Plano_Cadastro
		@p_NroInscricao 		= @p_NroInscricao
	,	@p_SeqCliente			= @p_SeqCliente
	,	@p_NroPlano			= @p_NroPlano
	,	@p_TipoRetorno			= @p_TipoRetorno			-- 1: Reingresso, 3: Regularização, 5: Decisão Judicial, 7: Adesão
	,	@p_StaDisableCheck		= @p_StaDisableCheck			--define que a migração poderá ser efetuada diretamente sem passar por críticas. Usado inicialmente para alterações em batch

	,	@p_StaMigracaoAutomatica	= @p_StaMigracaoAutomatica		--define se a migração está sendo feita em batch ou não
	,	@p_NroSitMigracaoAutomatica	= @p_NroSitMigracaoAutomatica		--define status da migração automática	--0: edição, 1: efetuada, 5: validação, 9: cancelada

	--,	@p_SeqClienteArray		= @p_SeqClienteArray			-- array com seq. de clientes que poderão retornar com o titular. Quando informado, o parâmetro @p_SeqCliente deve ser 0 - titular
	--,	@p_StaManterCanceladoArray	= @p_StaManterCanceladoArray		-- array com status usado para dependentes quando titular não solicita seu retorno

	,	@p_NmeUsuario			= @p_NmeUsuario

	,	@p_MsgError			= @MsgOutput output
	,	@p_StaSomenteValidacao		= @p_StaSomenteValidacao
	
	-- ** se existiram erros retorna para tela **
	if ( isnull( @MsgOutput, '' ) <> '' ) begin
		set @p_MsgOutput = @p_MsgOutput + @MsgOutput
		if ( @p_DisableRaiserror = 0 ) raiserror( @p_MsgOutput, 16, 1 )
		--<< mensagem específica da regra nº. 380 >> 
		IF @ProcessoEspecialLiminar = 0
			OR CHARINDEX( 'Retorno por “Decisão Judicial” não permitido. Objeto Liminar não Cadastrado', @p_MsgOutput ) > 0 
		RETURN 50000
	END
	
	-- ** se for somente validação retorna **
	if ( @p_StaSomenteValidacao = 1 ) begin
		if ( @p_DisableRaiserror = 0 ) raiserror( 77700, 16, 1 )		--operação efetuada
		return 77700
	end

	if @StartedTransaction = 0 begin transaction
	
	---- ** somente efetua o cancelamento se for uma migração completa **
	if ( @p_TipoOperacao = 0 ) begin

		-- ============================================================		
		-- ** CANCELAMENTO **
		-- ============================================================
		execute @Retorno			= dbo.cl_dbo_Cancela_Cadastro
			@p_NroInscricao 		= @p_NroInscricao
		,	@p_SeqCliente			= @p_SeqCliente		-- todos os beneficiários da inscrição
		,	@p_NroObs 			= 45			--MIGRAÇÃO PARA OUTRO PLANO--@NroObs
		,	@p_DtaCancelamento 		= @Date			-- hoje
		,	@p_DtaEvento			= null
		,	@p_StaMigracaoPlano		= 1	-- status que define se é ou não uma operação de migração
		,	@p_NmeUsuario			= @p_NmeUsuario
		,	@p_NroCPF			= @p_UserId
		,	@p_MsgError			= @MsgError
		
		if @Retorno > 0 begin
			set @Erro			= 1
			set @p_MsgOutput		= @p_MsgOutput + 'Erro no processo de cancelamento ' + isnull( @MsgError, '' )
		end
		
	end
	

	-- ========================================================================================================================
	-- ** RETORNO **
	-- ========================================================================================================================
	execute @Retorno			= dbo.cl_dbo_Retorna_Cadastro
		@p_NroInscricao 		= @p_NroInscricao
	,	@p_SeqCliente			= @p_SeqCliente--@SeqClienteC
	,	@p_NmeUsuario			= @p_NmeUsuario
	,	@p_NroCPFRespReingresso		= null				-- @p_UserIdRespReingresso	-- não será computado captação
	,	@p_NroCPF			= @p_UserId
	--,	@p_NroOlProprietario		= @NroUa			-- @D020NroOlProprietario
	,	@p_TipoRetorno			= @p_TipoRetorno		-- 1: Reingresso, 3: Regularização, 5: Decisão Judicial, 7: Migração
	,	@p_NmeMae			= @D030NmeMae--@NmeMaeC
	,	@p_StaDesvinculo		= 0				-- 1: Desvincula, 0: Não Desvincula
	,	@p_StaMigracaoPlano		= 1				-- migração de plano
	--,	@p_StaManterCancelado		= @StaManterCanceladoC		-- status usado para dependentes quando titular não solicita seu retorno
	,	@p_DtaCancelamentoProrrogacao	= null				-- usada apenas para Auto-Patrocínio
		
	,	@p_NroPlano			= @p_NroPlano
		
	if ( @Retorno > 0 ) begin
		set @Erro			= 1
		set @p_MsgOutput		= @p_MsgOutput +'Erro no processo de retorno'
	end

	
	-- ========================================================================================================================
	-- ** MIGRAÇÃO **
	-- ========================================================================================================================
	execute	@Retorno			= dbprogram.dbo.cl_dbo_Migra_Plano_Cadastro
		@p_NroInscricao 		= @p_NroInscricao
	,	@p_SeqCliente			= @p_SeqCliente--@SeqClienteC
	,	@p_NroPlano			= @p_NroPlano
	,	@p_NmeUsuario			= @p_NmeUsuario
	,	@p_StaMigracaoAutomatica	= @p_StaMigracaoAutomatica	--define se a migração está sendo feita em batch ou não
	,	@p_TipoRetorno			= @p_TipoRetorno
	,	@p_MsgError			= @MsgError output
		
		
	if ( @Retorno > 0 ) begin
		set @Erro			= 1
		set @p_MsgOutput		= @p_MsgOutput + ' ' + isnull( @MsgError, '' ) + ' Erro no processo de migracao'
	end

	
	if @SolicitacaoPortabilidadeDeferidaComPrazoAindaValido = 1 begin
		execute @Retorno				= dbo.cl_dbo_Beneficiario_Portabilidade_Plano_DAO
			@p_NroPortabilidadeCarencia		= @NroPortabilidadeCarencia
		,	@p_NroClientePortabilidadeCarencia	= NULL--@p_NroClientePortabilidadeCarencia
		,	@p_NroInscricao				= @p_NroInscricao
		,	@p_SeqCliente 				= @p_SeqCliente
		,	@p_NmeUsuario 				= @p_NmeUsuario 		
		,	@p_Operacao				= 'I'
		,	@p_UserId				= @p_Userid 		
		,	@p_DisableRaiseError			= 1
		,	@p_MsgErr				= @MsgReturn output
		
		if (@Retorno > 0 and @Retorno <> 77700) begin
			set @Erro			= 1
			set @p_MsgOutput		= @p_MsgOutput + ' ' + iif( @MsgReturn is null, '', @MsgReturn ) + ' Erro ao gravar dados da portabilidade de carência'
		end
	end
	
	-- ** verifica se houve erro efetivando ou não o processo **
	if @Erro <> 0 begin
		if @StartedTransaction = 0 and @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		if ( @p_DisableRaiserror = 0 ) raiserror( @p_MsgOutput, 16, 1 )	--operação não efetuada
		return 50000
	end else begin

		if @StartedTransaction = 0 and @@TRANCOUNT > 0 COMMIT TRANSACTION

		set @MsgReturn = 'Operação efetuada'
		
		set @MsgWarning = @MsgWarning + '''ATENÇÃO'': o lançamento do Pró-Rata tempore não foi gerado automaticamente. Após efetuar os acertos dos dados de arrecadação e corrigir o cadastro faça o lançamento manual.'

		-- ** regra nº. 374 **
		-- ** Incluir, para adesão e retorno, mensagem com texto “Verifique se há necessidade de inclusão ** 
		-- ** dos dados da pessoa legitimada a obter informações sobre o plano do titular, dependentes e **
		-- ** grupo familiar” para informar da possibilidade de cadastro de uma pessoa que possa ter acessar **
		-- ** as informações do plano do cliente caso ele deseje **
		set @MsgWarning = @MsgWarning + 'Verifique se há necessidade de inclusão dos dados da pessoa legitimada a obter informações sobre o plano do titular, dependentes e grupo familiar'

		
		--geração do pró-rata não deve ser feita conforme alinhamento feito com os analistas da arrecadação
		------ ====================================================================================
		------ ** GERAÇÃO DO PRÓ-RATA - AGREGADO
		------ ====================================================================================
		
	end

	-- ** retorno **
	if len(@MsgWarning) > 0 set @MsgReturn = @MsgReturn + @MsgWarning
		
	if ( @p_DisableRaiserror = 0 ) begin
		raiserror( @MsgReturn, 16, 1 )
	end
	RETURN 77700
	
-- ** operação 'S': SELECT **
end else begin

	--se titular retorna todos clientes VÁLIDOS na listagem
	if @p_SeqCliente = 0 set @p_SeqCliente = null
		
	--declare	@TableBeneficiarios		xml
	declare	@Table_Beneficiarios_retorno	table (
		NroInscricao			int		not null
	,	SeqCliente			tinyint		not null
	,	NroCpfCliente			numeric(11,0)	null
	,	CpfClienteOk			tinyint		null
	,	NmeCliente			varchar(70)	null
	,	NmeMae				varchar(70)	null
	,	DtaCancelamento			smalldatetime	null
	,	QtdCancelamento			tinyint		null
	,	NroObs				int		null
	,	MtvCancelamento			varchar(20)	null
	,	NroJstCancelamento		tinyint		null
	,	NmeJstCancelamento		varchar(50)	null
	,	DiasCancelados			int		null
	,	NroPlano			smallint	null
	,	NmePlano			varchar(50)	null
	,	StaAgregado			tinyint		null
	,	QtdDiaMaxRegularizacao		smallint	null
	,	StaRequerAutorizacao		tinyint		null
	,	StaPermiteRetornarMigrar	tinyint		null
	,	StaPermiteRegularizacao		tinyint		null
	,	OpcoesRetorno			varchar(128)	null
	,	StaAtivo			tinyint		null
	,	DesVinculo			varchar(128)	null
	,	StaPermiteOpcaoSeguroRemissao	tinyint		null
	,	StaMigrar			tinyint		null
	,	NmePlanoDestino			varchar(max)	null
		
	,	NroInsCoresponsavel		int		null
	,	ClientePossuiInternacao		tinyint		null
	,	StaRetornar			tinyint		null
	)

	insert	into @Table_Beneficiarios_retorno
	execute DBPROGRAM.dbo.[cl_fnc_Beneficiarios_Para_RetornarOuMigrar]
		@p_NroInscricao 		= @p_NroInscricao
	,	@p_SeqCliente			= @p_SeqCliente
	,	@p_UserId			= @p_UserId
	,	@p_StaRetorno			= 0
	,	@p_StaVerificaCpfReceita	= 1
	,	@p_StaVerificaInternacoes	= 0
	--,	@p_TableBeneficiarios		= @TableBeneficiarios output

	select	x.*
	from	@Table_Beneficiarios_retorno			as x
	where	(
		isnull( @p_Option, 0 ) = 0 and 
		( @p_NroInscricao = x.NroInscricao ) 
		AND	( @p_SeqCliente = x.SeqCliente or @p_SeqCliente IS NULL )
	) or (
		isnull( @p_Option, 0 ) = 1
		AND	( @p_NroInscricao = x.NroInsCoresponsavel )
	)
	order	by x.NroInscricao, x.SeqCliente
		
	return 0

end
go
PRINT 'FIM DA SP NO ' + @@SERVERNAME
go
