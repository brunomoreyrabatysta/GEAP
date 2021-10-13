
use DBPROGRAM
go
-----------------------------------------------------------------------------------------------
print 'procedure cl_usr_Verifica_Dados_Inscricao				Versão: '+CONVERT( VARCHAR(10), getdate(), 103 )
-----------------------------------------------------------------------------------------------
if exists (select * from sysobjects where id = object_id('cl_usr_Verifica_Dados_Inscricao') and sysstat & 0xf = 4)
	drop procedure cl_usr_Verifica_Dados_Inscricao
go

CREATE PROCEDURE cl_usr_Verifica_Dados_Inscricao
  @p_NroInscricao INT = NULL
, @p_SeqCliente TINYINT = NULL
, @p_NroSitCarencia TINYINT = NULL
, @p_ObsSitCarencia VARCHAR(60) = NULL
, @p_SglSexo VARCHAR(1) = NULL
, @p_DtaInscricao DATETIME = NULL
, @p_NroConveniada SMALLINT = NULL
, @p_NroSituacao SMALLINT = NULL
, @p_DtaNascimento DATETIME = NULL
, @p_NroVinculo SMALLINT = NULL
, @p_NroInsCoresponsavel INT = NULL
, @p_NroVncCoresponsavel TINYINT = NULL
, @p_DtaAdmissao DATETIME = NULL
, @p_NmeCliente CHAR(70) = NULL
, @p_NmeCartao VARCHAR(23) = NULL
, @p_NmeMae CHAR(70) = NULL
, @p_NmePai VARCHAR(70) = NULL
, @p_Operacao VARCHAR(1) = NULL
, @p_PreInscricaoInternet TINYINT = 0		--status que indica se é uma pré-inscrição cadastral feita pela internet (quando ativo somente efetua críticas e não grava dados)
, @p_StaExtratoImpresso TINYINT = NULL
, @p_NroPeriodoExtratoImpresso TINYINT = NULL
, @p_StaAdocao TINYINT = NULL
, @p_DtaAdocao DATETIME = NULL
, @p_NroCpfCliente NUMERIC(11, 0) = NULL
, @p_NroSiapeInstituidor VARCHAR(10) = NULL
, @p_StaDisableCheck TINYINT = 0

, @p_MsgToUser VARCHAR(MAX) = '' OUTPUT
, @p_NroCasoIsencaoCarencia TINYINT = NULL OUTPUT
, @p_StaVerificaRegraNomeAns CHAR(1) = NULL
, @p_NroPlano SMALLINT = NULL
, @p_NroCusteio TINYINT = NULL
, @p_CodArrContribuicao SMALLINT = NULL
, @p_UserId NUMERIC(11, 0) = NULL
AS

	SET NOCOUNT ON

	-- ** declaração de variáveis **
	DECLARE @Retorno INT = 0
		   ,@Erro TINYINT
		   ,@Date DATETIME
		   ,@MsgValidation VARCHAR(512)
		   ,@msg VARCHAR(200)
		   ,@NroTpoOperacao TINYINT		--operação a ser executada: 2: manutenção, 4: adesão, 8: retorno, 16: migração, 32: atualização cadastral, 64: cancelamento

			-- ** variáveis para função de check **
		   ,@D020DtaComunicacaoInequivoca DATETIME
		   ,@D020NroSituacao SMALLINT
		   ,@D020NroVncCoresponsavel TINYINT
		   ,@D020NroConveniada SMALLINT

		   ,@D027DtaConvenio DATETIME

			-- ** dado do cliente **
		   ,@D030NroObs TINYINT
		   ,@D030DtaCancelamento SMALLDATETIME
		   ,@D030NroVinculo TINYINT
		   ,@D030NroSitCarencia TINYINT



	-- ** inicialização de variáveis **
	SET @Date = CONVERT(VARCHAR(8), GETDATE(), 112)
	SET @p_MsgToUser = ''
	SET @Erro = 0
	SET @NroTpoOperacao = 0

	IF @p_SeqCliente IS NULL
		SET @p_SeqCliente = 0

	-- ** se não for pré-inscrição, usa o database 'cadastro_cliente' - normal **
	IF (@p_PreInscricaoInternet = 0)
	BEGIN

		-- adesão de pensionista e dependente do instituidor
		IF @p_Operacao = 'I'
			AND @p_NroSituacao IN (3, 16)
			AND ISNULL(@p_NroSiapeInstituidor, '') <> ''
		BEGIN
			SELECT
				@p_NroInscricao = b.NroInscricao
			FROM CADASTRO_CLIENTE.dbo.D030_CLIENTE b WITH (NOLOCK)
			WHERE b.SeqCliente = 0
			AND (b.DtaCancelamento IS NOT NULL
			AND b.DtaCancelamento < GETDATE())
			AND b.NroObs = 6	--falecimento
			AND LTRIM(RTRIM(b.CodMatricula)) = LTRIM(RTRIM(@p_NroSiapeInstituidor))
		END

		SELECT
			@D020DtaComunicacaoInequivoca = D020.DtaComunicacaoInequivoca
		FROM CADASTRO_CLIENTE.dbo.D020_INSCRICAO D020 WITH (NOLOCK)
		INNER JOIN CADASTRO_CLIENTE.dbo.CL83_HISTORICO_CLIENTE_PLANO CL83 WITH (NOLOCK)
			ON CL83.NroInscricao = D020.NroInscricao
				AND CL83.SeqCliente = 0
				AND CL83.NroHstPosterior IS NULL
				AND CL83.DtaFimValidade IS NULL
		INNER JOIN PLANO_SAUDE.dbo.PS71_PLANO PS71 WITH (NOLOCK)
			ON CL83.NroPlano = PS71.NroPlano
		WHERE D020.NroInscricao = IIF(@p_Operacao = 'I'
		AND @p_NroInsCoresponsavel IS NOT NULL, @p_NroInsCoresponsavel, @p_NroInscricao)
	END

	IF @p_Operacao = 'U'
	BEGIN

		SELECT
			@D030NroObs = x.NroObs
		   ,@D030DtaCancelamento = x.DtaCancelamento
		   ,@D030NroVinculo = x.NroVinculo
		   ,@D030NroSitCarencia = x.NroSitCarencia
		   ,@D020NroSituacao = x.NroSituacao
		   ,@D020NroVncCoresponsavel = x.NroVncCoresponsavel
		   ,@D027DtaConvenio = x.DtaConvenio
		   ,@D020NroConveniada = x.NroConveniada

		FROM DBPROGRAM.dbo.cl_fnc_InformacoesBasicasCliente(@p_NroInscricao, 0, DEFAULT, 0) x

	END
	ELSE
	BEGIN
		SELECT
			@D030NroObs = NULL
		   ,@D030DtaCancelamento = NULL
		   ,@D030NroVinculo = @p_NroVinculo
		   ,@D030NroSitCarencia = @p_NroSitCarencia
		   ,@D020NroSituacao = @p_NroSituacao
		   ,@D020NroVncCoresponsavel = @p_NroVncCoresponsavel
		   ,@D020NroConveniada = @p_NroConveniada

		SELECT
			@D027DtaConvenio = D027.DtaConvenio
		FROM PLANO_SAUDE.dbo.D027_CONVENIADA D027
		WHERE D027.NroConveniada = @p_NroConveniada
	END

	IF (@p_NroSituacao IS NULL)
		SET @p_NroSituacao = @D020NroSituacao
	IF (@p_NroVinculo != @D030NroVinculo
		OR @p_NroVncCoresponsavel <> @D020NroVncCoresponsavel)
		SET @NroTpoOperacao = @NroTpoOperacao + 2
	IF (@p_Operacao = 'I')
		SET @NroTpoOperacao = @NroTpoOperacao + 4
	IF @NroTpoOperacao = 0
		SET @NroTpoOperacao = 32


	-- ** regra nº. 16 **
	SET @MsgValidation = dbo.cl_fnc_ObservacaoSituacaoCarenciaValida(@p_NroSitCarencia, ISNULL(@p_ObsSitCarencia, ''))
	IF (@MsgValidation <> '')
	BEGIN
		SET @Erro = 1
		SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
	END

	--if ( ( @p_Operacao = 'I' or @p_NroSitCarencia <> @D030NroSitCarencia ) and @p_NroSitCarencia = 128 ) begin
	IF (@p_NroSitCarencia = 128)
	BEGIN
		SELECT
			@MsgValidation = x.MsgValidation
		   ,@p_NroCasoIsencaoCarencia = x.NroCasoIsencaoCarencia
		FROM dbo.cl_fnc_IsencaoTotalCarenciaValida(
		@p_NroInscricao
		, @p_SeqCliente
		, @p_DtaAdmissao
		, @p_DtaInscricao
		, @p_NroVinculo
		, @p_DtaNascimento
		, @p_StaAdocao
		, @p_DtaAdocao
		, @D020DtaComunicacaoInequivoca
		, @p_NroCpfCliente
		, @p_NroSituacao
		, @p_NroSitCarencia
		, IIF(@p_NroInsCoresponsavel IS NULL, 0, 1)
		, @p_NmeMae
		, @p_NmePai
		, @p_NroInsCoresponsavel
		--,	@D027DtaConvenio
		, @D020NroConveniada
		, @p_StaDisableCheck
		--,	@p_Operacao
		, NULL--@p_UserId		a carência somente é alterada pelo processo do beneficiário (cliente)

		, @p_NroPlano
		, @p_NroCusteio
		, @p_CodArrContribuicao
		, @NroTpoOperacao
		) AS x
		IF (@MsgValidation <> '')
		BEGIN
			SET @Erro = 1
			SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
		END
	END

	-- ** regra nº. 21 **
	SET @MsgValidation = dbo.cl_fnc_SituacaoCarenciaPartoValida(@p_NroSitCarencia, @p_SglSexo, @p_DtaInscricao, @D027DtaConvenio, @p_DtaAdmissao)
	IF (@MsgValidation <> '')
	BEGIN
		SET @Erro = 1
		SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
	END


	-- ** regra nº. 4 **
	SET @MsgValidation = dbo.cl_fnc_DataInscricaoValida(@p_DtaInscricao, @p_DtaNascimento, @NroTpoOperacao)
	IF (@MsgValidation <> '')
	BEGIN
		SET @Erro = 1
		SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
	END


	-- ** regra nº. 319 **
	SET @MsgValidation = dbo.cl_fnc_DataNascimentoValida(@p_DtaNascimento)
	IF (@MsgValidation <> '')
	BEGIN
		SET @Erro = 1
		SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
	END

	-- ** regra nº. 27 **
	IF (@p_Operacao = 'U'
		AND @D030DtaCancelamento IS NOT NULL
		AND @D030DtaCancelamento < GETDATE())
	BEGIN
		SET @MsgValidation = dbo.cl_fnc_AlteracaoDiretaInscricaoCanceladaValida(@p_NroVinculo, @D030NroObs, NULL, @p_PreInscricaoInternet)
		IF (@MsgValidation <> '')
		BEGIN
			SET @Erro = 1
			SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
		END
	END
	-- ** regra data de nascimento até 18 anos, caso retorno do serpro seja 422 lgpd **
	-- ** Se o cpf de o retorno 422, verifica se a data de nascimento é até 18 anos,
	-- **    se não verificar o nome e data de nascimento conforme retorno.



  /*
  Alteração: Bruno Moreira Batista
  Corrigindo o parâmetro a ser passado
  */
	EXECUTE @Retorno = DBPROGRAM.dbo.cl_usr_Verifica_Cpf @p_NroCpfCliente = @p_NroCpfCliente
														 --, @p_NmeCliente		=	@NmeCliente output
														 --, @p_DtaNascimento	=	@DtaNascimento output
														 --, @p_SituacaoCpfCliente =	@SituacaoCpfCliente output
														,@p_msg = @msg OUTPUT
														 --, @p_NroLog		=	@NroLog output
														,@p_UserId = 0
	--, @p_UtilizarApiSerpro	= 0
	IF (@Retorno = 500
		AND @msg LIKE '%(422)%')
	BEGIN
		IF (DBPROGRAM.dbo.fn_dbo_CalcularIdade(@p_DtaNascimento) >= 18)
		BEGIN
			SET @Erro = 1
			SET @p_MsgToUser = @p_MsgToUser + 'A idade da data de nascimento informada é igual ou superior a 18 anos , corrija, pois cpf cadastrado é de menor - LGPD - SERPRO.'
		END
	END
	ELSE
	BEGIN
		IF (@p_Operacao = 'U')
		BEGIN
			EXECUTE @Retorno = DBPROGRAM.dbo.cl_chk_Valida_Dados_Receita_Federal @p_NroInscricao = @p_NroInscricao
																				,@p_SeqCliente = @p_SeqCliente
																				,@p_NroCpfCliente = @p_NroCpfCliente
																				,@p_DtaNascimento = @p_DtaNascimento
																				,@p_NmeCliente = @p_NmeCliente
																				,@p_MsgError = @MsgValidation OUTPUT
																				,@p_UserId = @p_UserId

			IF (@Retorno <> 0)
			BEGIN
				SET @Erro = 1
				SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
			END
		END
	END




	-- ** regra nº. 356 **
	IF (ISNULL(@p_StaVerificaRegraNomeAns, 0) != 0
		AND @p_StaVerificaRegraNomeAns = '1')
	BEGIN
		SET @MsgValidation = dbo.cl_fnc_NomePadraoAnsValida(@p_NmeCliente, 'B')
		IF (@MsgValidation <> '')
		BEGIN
			SET @Erro = 1
			SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
		END
	END
	SET @MsgValidation = dbo.cl_fnc_NomePadraoAnsValida(@p_NmeMae, 'M')
	IF (@MsgValidation <> '')
	BEGIN
		SET @Erro = 1
		SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
	END


	SET @MsgValidation = dbo.cl_fnc_NomePadraoAnsValida(@p_NmeCartao, 'C')
	IF (@MsgValidation <> '')
	BEGIN
		SET @Erro = 1
		SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
	END


	SET @MsgValidation = dbo.cl_fnc_NomePadraoAnsValida(@p_NmePai, 'P')
	IF (@MsgValidation <> '')
	BEGIN
		SET @Erro = 1
		SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
	END


	-- ** regra nº. 358 **
	SET @MsgValidation = dbo.cl_fnc_ExtratoParticipacaoValida(@p_StaExtratoImpresso, @p_NroPeriodoExtratoImpresso)
	IF (@MsgValidation <> '')
	BEGIN
		SET @Erro = 1
		SET @p_MsgToUser = @p_MsgToUser + @MsgValidation
	END


	SET @Retorno = @Erro
	RETURN @Retorno

go
PRINT 'FIM DA SP NO ' + @@SERVERNAME
go
