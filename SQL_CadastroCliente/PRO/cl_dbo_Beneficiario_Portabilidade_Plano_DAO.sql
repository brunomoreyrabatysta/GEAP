
use DBPROGRAM
go
-----------------------------------------------------------------------------------------------
print 'procedure cl_dbo_Beneficiario_Portabilidade_Plano_DAO				Versão: '+CONVERT( VARCHAR(10), getdate(), 103 )
-----------------------------------------------------------------------------------------------
if exists (select * from sysobjects where id = object_id('cl_dbo_Beneficiario_Portabilidade_Plano_DAO') and sysstat & 0xf = 4)
	drop procedure cl_dbo_Beneficiario_Portabilidade_Plano_DAO
go


create procedure dbo.cl_dbo_Beneficiario_Portabilidade_Plano_DAO
	@p_NroPortabilidadeCarencia		int		= Null
,	@p_NroClientePortabilidadeCarencia	int		= Null
,	@p_NroInscricao				int		= Null
,	@p_SeqCliente 				smallint	= Null

,	@p_Operacao				char (1)	= Null
,	@p_UserId				numeric(11,0)	= Null
,	@p_DisableRaiseError			bit		= 0
,	@p_MsgErr				varchar(8000)	= '' output
as
Set nocount on
if ( @p_NroPortabilidadeCarencia is null or ( @p_Operacao <> 'I' and @p_NroClientePortabilidadeCarencia is null )
	or @p_NroInscricao is null or @p_SeqCliente is null
) begin
	execute dbo.ss_dbo_MsgErro
		@p_NroError = 77705
	,	@p_Operacao = @p_Operacao
	,	@p_Funcao = 'dbo.cl_dbo_Beneficiario_Portabilidade_Plano_DAO'
	return(77705)
End

-- ** declaração de variáveis **
Declare	@Retorno	int			= 0
,	@msgErr		varchar(8000)		 = ''

-- ** inicializa variavel **




if (@p_Operacao = 'D') begin
	if exists (	select *
		from	CADASTRO_CLIENTE.DBO.CL61_PORTABILIDADE_CARENCIA
		where	NroPortabilidadeCarencia = @p_NroPortabilidadeCarencia) begin
		delete	CADASTRO_CLIENTE.DBO.CL61_PORTABILIDADE_CARENCIA
		where	NroPortabilidadeCarencia = @p_NroPortabilidadeCarencia
		select @Retorno = @@Error
	end else begin
		select @Retorno = 77701
	end
	
end else begin
	
	-- Faz a crítica para gravação da CL60_CLIENTE_PORTABILIDADE_CARENCIA
	--
	execute	@Retorno					= dbo.cl_chk_SaveCL60_CLIENTE_PORTABILIDADE_CARENCIA
 		@p_NroClientePortabilidadeCarencia		= @p_NroClientePortabilidadeCarencia
	,	@p_NroPortabilidadeCarencia			= @p_NroPortabilidadeCarencia
	,	@p_NroInscricao					= @p_NroInscricao
	,	@p_SeqCliente 					= @p_SeqCliente
	
	,	@p_Operacao 					= @p_Operacao
	,	@p_UserID					= @p_UserId
	,	@p_DisableRaiseError				= @p_DisableRaiseError
	,	@p_MsgErr					= @msgErr output

	if @Retorno = 0 begin
	
		-- Faz a crítica para gravação da portabilidade
		--
		execute	@Retorno				= dbo.cl_chk_Beneficiario_Portabilidade_Plano
 			@p_NroPortabilidadeCarencia		= @p_NroPortabilidadeCarencia
		,	@p_NroClientePortabilidadeCarencia	= @p_NroClientePortabilidadeCarencia
		,	@p_NroInscricao				= @p_NroInscricao
		,	@p_SeqCliente 				= @p_SeqCliente
		
		,	@p_Operacao 				= @p_Operacao
		,	@p_UserID				= @p_UserId
		,	@p_DisableRaiseError			= @p_DisableRaiseError
		,	@p_MsgErr				= @msgErr output

	
		if @Retorno = 0 begin
			
			--atualiza informações como QtdPortabilidade se deferida
			execute @Retorno 				= dbo.cl_dbo_Beneficiario_Portabilidade_Plano
				@p_NroPortabilidadeCarencia		= @p_NroPortabilidadeCarencia
			,	@p_NroClientePortabilidadeCarencia	= @p_NroClientePortabilidadeCarencia
			,	@p_NroInscricao				= @p_NroInscricao
			,	@p_SeqCliente 				= @p_SeqCliente
			,	@p_UserID				= @p_UserId
			
		end
		
	end
	
end

return @Retorno

--	Fim do Arquivo dbo.cl_usr_Beneficiario_Portabilidade_Plano
PRINT 'FIM DA SP NO ' + @@SERVERNAME
GO