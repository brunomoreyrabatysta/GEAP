
use DBPROGRAM
go
-----------------------------------------------------------------------------------------------
print 'procedure cl_dbo_Migra_Plano_Cadastro_DAO				Vers�o: '+CONVERT( VARCHAR(10), getdate(), 103 )
-----------------------------------------------------------------------------------------------
if exists (select * from sysobjects where id = object_id('cl_dbo_Migra_Plano_Cadastro_DAO') and sysstat & 0xf = 4)
	drop procedure cl_dbo_Migra_Plano_Cadastro_DAO
go

create procedure cl_dbo_Migra_Plano_Cadastro_DAO
	@p_NroInscricao 		int 		= null
,	@p_SeqCliente 			smallint 	= Null
,	@p_NroPlano			smallint 	= null
,	@p_TipoOperacao			tinyint		= null	-- 0: Migra��o de Plano, 1: Retorno com Migra��o de Plano
,	@p_TipoRetorno			tinyint		= null	-- 1: Reingresso, 3: Regulariza��o, 5: Decis�o Judicial, 7: Ades�o
,	@p_StaGeraProRataAutomatico	tinyint		= 1	-- status para indicar gera��o autom�tica ou n�o de pr�-rata
,	@p_StaDisableCheck		tinyint		= 0	--define que a migra��o poder� ser efetuada diretamente sem passar por cr�ticas. Usado inicialmente para altera��es em batch

,	@p_StaMigracaoAutomatica	tinyint		= 0	--define se a migra��o est� sendo feita em batch ou n�o
,	@p_NroSitMigracaoAutomatica	tinyint		= 0	--define status da migra��o autom�tica	--0: edi��o, 1: efetuada, 5: valida��o, 9: cancelada
,	@p_MsgOutput			varchar(2048)	= ''	output
,	@p_DisableRaiserror		tinyint		= 0	--define se a fun��o raiserror ser� ou n�o executada
,	@p_StaSomenteValidacao		tinyint		= 0	-- define se haver� somente valida��o das regras ou efetuar� o retorno por completo

,	@p_UserId	 numeric(11,0)
,	@p_Operacao			char(1)		= null
,	@p_NmeUsuario			varchar(32)	= null
,	@p_Option			tinyint		= 0
as
/*
	@p_TipoOperacao: descreve o tipo de opera��o que est� sendo executada no cadastro de clientes:
		- 0: Migra��o de Plano
		- 1: Retorno com Migra��o de Plano

*/
set nocount on

-- ** verifica par�metro(s) obrigat�rio(s) **
if ( @p_NroInscricao is null or ( @p_Operacao = 'E' and ( @p_NroPlano is null or @p_SeqCliente is null ) ) ) begin
	raiserror( 'Par�metros insuficientes para a opera��o solicitada', 10,  1 )
	return 50000
end


-- ** declara��o de vari�veis **
declare @Retorno			int
,	@Erro				int


if ( @p_Operacao = 'E' ) begin

	-- ** declara��o de vari�veis **
	declare @Date 					datetime
	,	@NroUa					smallint
	,	@MsgOutput				varchar(2048)
	,	@MsgWarning				varchar(1024)
	,	@MsgReturn				varchar(2560)
	--,	@NroObs					tinyint
	,	@MsgError				varchar(1024)
	,	@StartedTransaction			smallint
	,	@ProcessoEspecialLiminar		BIT		= 0	--super usu�rio

	-- ** D030 **
	,	@D030NmeMae				char(70)
	,	@D030NroCpfCliente			numeric(11,0)
	
	-- ** PS71 **
	,	@PS71StaAgregado			tinyint
	
	--portabilidde
	,	@NroPortabilidadeCarencia		int
	,	@SolicitacaoPortabilidadeDeferidaComPrazoAindaValido	tinyint	= 0

	
	-- ** inicializa vari�veis **
	--set @Erro					= 0
	set @Date 					= getdate()
	set @MsgOutput					= ''
	set @MsgWarning					= ''
	set @MsgReturn 					= ''
	set @MsgError					= ''
	set @StartedTransaction				= XACT_STATE()
	set @p_TipoRetorno				= iif( @p_TipoRetorno is null, 3, @p_TipoRetorno )	--3: Regulariza��o
	set @p_TipoOperacao				= iif( @p_TipoRetorno = 3, 0, 1 )
	


	-- ** ======================================================================================================================
	-- ** RECUPERA VALORES **
	-- ** ======================================================================================================================
	
	-- ** recupera vari�veis necess�rias para cr�ticas/atualiza��es **
	SELECT	@D030NmeMae								= x.NmeMae
	,	@D030NroCpfCliente							= x.NroCpfCliente
	,	@PS71StaAgregado							= x.StaAgregado
	from	DBPROGRAM.dbo.cl_fnc_InformacoesBasicasCliente( @p_NroInscricao, @p_SeqCliente, null, 0 ) as x
	
	-- ** regra n�. 380 **
	-- ** O retorno de um benefici�rio em decorr�ncia de uma liminar judicial seja na mesma inscri��o **
	-- ** ou numa nova inscri��o � manuten��o � requer a exist�ncia de um objeto liminar cadastrado e **
	-- ** que o tipo de retorno seja �Decis�o Judicial�. Caso n�o exista liminar, exibir mensagem: **
	-- ** �OBJETO LIMINAR N�O CADASTRADO�. O retorno por liminar judicial dever� se sobrepor a qualquer **
	-- ** outra regra que o impe�a de ser efetivado. No caso de retorno noutra inscri��o, as informa��es **
	-- ** da liminar, cadastradas na inscri��o anterior, dever�o ser copiadas para a nova tamb�m **
	EXECUTE	@ProcessoEspecialLiminar = DBPROGRAM.dbo.cl_fnc_RetornoDevidoLiminar @p_NroInscricao, 0, 3--@p_TipoRetorno

	
	--recupera informa��es de portabilidade
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
	-- ** REGRAS DE NEG�CIO **
	-- ============================================================
	execute @Retorno			= dbo.cl_chk_Migra_Plano_Cadastro
		@p_NroInscricao 		= @p_NroInscricao
	,	@p_SeqCliente			= @p_SeqCliente
	,	@p_NroPlano			= @p_NroPlano
	,	@p_TipoRetorno			= @p_TipoRetorno			-- 1: Reingresso, 3: Regulariza��o, 5: Decis�o Judicial, 7: Ades�o
	,	@p_StaDisableCheck		= @p_StaDisableCheck			--define que a migra��o poder� ser efetuada diretamente sem passar por cr�ticas. Usado inicialmente para altera��es em batch

	,	@p_StaMigracaoAutomatica	= @p_StaMigracaoAutomatica		--define se a migra��o est� sendo feita em batch ou n�o
	,	@p_NroSitMigracaoAutomatica	= @p_NroSitMigracaoAutomatica		--define status da migra��o autom�tica	--0: edi��o, 1: efetuada, 5: valida��o, 9: cancelada

	--,	@p_SeqClienteArray		= @p_SeqClienteArray			-- array com seq. de clientes que poder�o retornar com o titular. Quando informado, o par�metro @p_SeqCliente deve ser 0 - titular
	--,	@p_StaManterCanceladoArray	= @p_StaManterCanceladoArray		-- array com status usado para dependentes quando titular n�o solicita seu retorno

	,	@p_NmeUsuario			= @p_NmeUsuario

	,	@p_MsgError			= @MsgOutput output
	,	@p_StaSomenteValidacao		= @p_StaSomenteValidacao
	
	-- ** se existiram erros retorna para tela **
	if ( isnull( @MsgOutput, '' ) <> '' ) begin
		set @p_MsgOutput = @p_MsgOutput + @MsgOutput
		if ( @p_DisableRaiserror = 0 ) raiserror( @p_MsgOutput, 16, 1 )
		--<< mensagem espec�fica da regra n�. 380 >> 
		IF @ProcessoEspecialLiminar = 0
			OR CHARINDEX( 'Retorno por �Decis�o Judicial� n�o permitido. Objeto Liminar n�o Cadastrado', @p_MsgOutput ) > 0 
		RETURN 50000
	END
	
	-- ** se for somente valida��o retorna **
	if ( @p_StaSomenteValidacao = 1 ) begin
		if ( @p_DisableRaiserror = 0 ) raiserror( 77700, 16, 1 )		--opera��o efetuada
		return 77700
	end

	if @StartedTransaction = 0 begin transaction
	
	---- ** somente efetua o cancelamento se for uma migra��o completa **
	if ( @p_TipoOperacao = 0 ) begin

		-- ============================================================		
		-- ** CANCELAMENTO **
		-- ============================================================
		execute @Retorno			= dbo.cl_dbo_Cancela_Cadastro
			@p_NroInscricao 		= @p_NroInscricao
		,	@p_SeqCliente			= @p_SeqCliente		-- todos os benefici�rios da inscri��o
		,	@p_NroObs 			= 45			--MIGRA��O PARA OUTRO PLANO--@NroObs
		,	@p_DtaCancelamento 		= @Date			-- hoje
		,	@p_DtaEvento			= null
		,	@p_StaMigracaoPlano		= 1	-- status que define se � ou n�o uma opera��o de migra��o
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
	,	@p_NroCPFRespReingresso		= null				-- @p_UserIdRespReingresso	-- n�o ser� computado capta��o
	,	@p_NroCPF			= @p_UserId
	--,	@p_NroOlProprietario		= @NroUa			-- @D020NroOlProprietario
	,	@p_TipoRetorno			= @p_TipoRetorno		-- 1: Reingresso, 3: Regulariza��o, 5: Decis�o Judicial, 7: Migra��o
	,	@p_NmeMae			= @D030NmeMae--@NmeMaeC
	,	@p_StaDesvinculo		= 0				-- 1: Desvincula, 0: N�o Desvincula
	,	@p_StaMigracaoPlano		= 1				-- migra��o de plano
	--,	@p_StaManterCancelado		= @StaManterCanceladoC		-- status usado para dependentes quando titular n�o solicita seu retorno
	,	@p_DtaCancelamentoProrrogacao	= null				-- usada apenas para Auto-Patroc�nio
		
	,	@p_NroPlano			= @p_NroPlano
		
	if ( @Retorno > 0 ) begin
		set @Erro			= 1
		set @p_MsgOutput		= @p_MsgOutput +'Erro no processo de retorno'
	end

	
	-- ========================================================================================================================
	-- ** MIGRA��O **
	-- ========================================================================================================================
	execute	@Retorno			= dbprogram.dbo.cl_dbo_Migra_Plano_Cadastro
		@p_NroInscricao 		= @p_NroInscricao
	,	@p_SeqCliente			= @p_SeqCliente--@SeqClienteC
	,	@p_NroPlano			= @p_NroPlano
	,	@p_NmeUsuario			= @p_NmeUsuario
	,	@p_StaMigracaoAutomatica	= @p_StaMigracaoAutomatica	--define se a migra��o est� sendo feita em batch ou n�o
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
		
		,	@p_Operacao				= 'I'
		,	@p_UserId				= @p_Userid 		
		,	@p_DisableRaiseError			= 1
		,	@p_MsgErr				= @MsgReturn output
		
		if (@Retorno > 0 and @Retorno <> 77700) begin
			set @Erro			= 1
			set @p_MsgOutput		= @p_MsgOutput + ' ' + iif( @MsgReturn is null, '', @MsgReturn ) + ' Erro ao gravar dados da portabilidade de car�ncia'
		end
	end
	
	-- ** verifica se houve erro efetivando ou n�o o processo **
	if @Erro <> 0 begin
		if @StartedTransaction = 0 and @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		if ( @p_DisableRaiserror = 0 ) raiserror( @p_MsgOutput, 16, 1 )	--opera��o n�o efetuada
		return 50000
	end else begin

		if @StartedTransaction = 0 and @@TRANCOUNT > 0 COMMIT TRANSACTION

		set @MsgReturn = 'Opera��o efetuada'
		
		set @MsgWarning = @MsgWarning + '''ATEN��O'': o lan�amento do Pr�-Rata tempore n�o foi gerado automaticamente. Ap�s efetuar os acertos dos dados de arrecada��o e corrigir o cadastro fa�a o lan�amento manual.'

		-- ** regra n�. 374 **
		-- ** Incluir, para ades�o e retorno, mensagem com texto �Verifique se h� necessidade de inclus�o ** 
		-- ** dos dados da pessoa legitimada a obter informa��es sobre o plano do titular, dependentes e **
		-- ** grupo familiar� para informar da possibilidade de cadastro de uma pessoa que possa ter acessar **
		-- ** as informa��es do plano do cliente caso ele deseje **
		set @MsgWarning = @MsgWarning + 'Verifique se h� necessidade de inclus�o dos dados da pessoa legitimada a obter informa��es sobre o plano do titular, dependentes e grupo familiar'

		
		--gera��o do pr�-rata n�o deve ser feita conforme alinhamento feito com os analistas da arrecada��o
		------ ====================================================================================
		------ ** GERA��O DO PR�-RATA - AGREGADO
		------ ====================================================================================
		
	end

	-- ** retorno **
	if len(@MsgWarning) > 0 set @MsgReturn = @MsgReturn + @MsgWarning
		
	if ( @p_DisableRaiserror = 0 ) begin
		raiserror( @MsgReturn, 16, 1 )
	end
	RETURN 77700
	
-- ** opera��o 'S': SELECT **
end else begin

	--se titular retorna todos clientes V�LIDOS na listagem
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
