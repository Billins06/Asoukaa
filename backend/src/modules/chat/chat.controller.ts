import {
  Controller,
  Get,
  Post,
  Patch,
  Body,
  Param,
  Query,
  Req,
  UseGuards,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
  ApiQuery,
} from '@nestjs/swagger';
import type { Request } from 'express';

import { ChatService }            from './chat.service';
import { CreateConversationDto }  from './dto/create-conversation.dto';
import { SendMessageDto }         from './dto/send-message.dto';
import { JwtAuthGuard }           from '../auth/guards/jwt-auth.guard';
import { RolesGuard }             from '../auth/guards/roles.guard';
import { Roles }                  from '../auth/decorators/roles.decorator';
import { Role }                   from '../../common/enums/role.enum';

const getUser = (req: Request): any => (req as any).user;

@ApiTags('Chat')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('chat')
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  // ─── Routes Utilisateur ───────────────────────────────

  @ApiOperation({ summary: 'Créer ou récupérer une conversation' })
  @Post('conversations')
  @HttpCode(HttpStatus.CREATED)
  createConversation(
    @Req() req: Request,
    @Body() dto: CreateConversationDto,
  ) {
    return this.chatService.createConversation(getUser(req).id, dto);
  }

  @ApiOperation({ summary: 'Mes conversations' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('conversations')
  getMyConversations(
    @Req() req: Request,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.chatService.getMyConversations(
      getUser(req).id,
      Number(page)  || 1,
      Number(limit) || 20,
    );
  }

  @ApiOperation({ summary: 'Messages d\'une conversation' })
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('conversations/:id/messages')
  getMessages(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.chatService.getMessages(
      getUser(req).id,
      id,
      Number(page)  || 1,
      Number(limit) || 50,
    );
  }

  @ApiOperation({ summary: 'Envoyer un message' })
  @Post('conversations/:id/messages')
  @HttpCode(HttpStatus.CREATED)
  sendMessage(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: SendMessageDto,
  ) {
    return this.chatService.sendMessage(getUser(req).id, id, dto);
  }

  @ApiOperation({ summary: 'Signaler un message' })
  @Patch('messages/:id/report')
  @HttpCode(HttpStatus.OK)
  reportMessage(
    @Req() req: Request,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.chatService.reportMessage(getUser(req).id, id);
  }

  // ─── Routes Admin ─────────────────────────────────────

  @ApiOperation({ summary: '[ADMIN] Conversations signalées' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @ApiQuery({ name: 'page',  required: false })
  @ApiQuery({ name: 'limit', required: false })
  @Get('reported')
  getReportedConversations(
    @Query('page')  page?:  number,
    @Query('limit') limit?: number,
  ) {
    return this.chatService.getReportedConversations(
      Number(page)  || 1,
      Number(limit) || 20,
    );
  }

  @ApiOperation({ summary: '[ADMIN] Messages signalés d\'une conversation' })
  @UseGuards(RolesGuard)
  @Roles(Role.ADMIN)
  @Get('reported/:id/messages')
  getReportedMessages(@Param('id', ParseUUIDPipe) id: string) {
    return this.chatService.getReportedMessages(id);
  }
}