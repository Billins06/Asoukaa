import {
  Controller,
  Post,
  Param,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  UploadedFiles,
  HttpCode,
  HttpStatus,
  BadRequestException,
} from '@nestjs/common';
import {
  FileInterceptor,
  FilesInterceptor,
} from '@nestjs/platform-express';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
  ApiConsumes,
  ApiBody,
} from '@nestjs/swagger';

import { UploadService, UploadType } from './upload.service';
import { JwtAuthGuard }              from '../auth/guards/jwt-auth.guard';

@ApiTags('Upload')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('upload')
export class UploadController {
  constructor(private readonly uploadService: UploadService) {}

  // ─── Upload d'un seul fichier ─────────────────────────

  @ApiOperation({ summary: 'Uploader un fichier (image ou PDF)' })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        file: { type: 'string', format: 'binary' },
      },
    },
  })
  @Post(':type')
  @UseInterceptors(FileInterceptor('file'))
  @HttpCode(HttpStatus.CREATED)
  uploadFile(
    @Param('type') type: string,
    @UploadedFile() file: Express.Multer.File,
  ) {
    // Vérifier que le type est valide
    if (!Object.values(UploadType).includes(type as UploadType)) {
      throw new BadRequestException(
        `Type d'upload invalide. Valeurs acceptées : ${Object.values(UploadType).join(', ')}`
      );
    }

    return this.uploadService.uploadFile(file, type as UploadType);
  }

  // ─── Upload de plusieurs fichiers ─────────────────────

  @ApiOperation({ summary: 'Uploader plusieurs fichiers (max 10)' })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        files: {
          type:  'array',
          items: { type: 'string', format: 'binary' },
        },
      },
    },
  })
  @Post(':type/multiple')
  @UseInterceptors(FilesInterceptor('files', 10))
  @HttpCode(HttpStatus.CREATED)
  uploadMultiple(
    @Param('type') type: string,
    @UploadedFiles() files: Express.Multer.File[],
  ) {
    if (!Object.values(UploadType).includes(type as UploadType)) {
      throw new BadRequestException(
        `Type d'upload invalide. Valeurs acceptées : ${Object.values(UploadType).join(', ')}`
      );
    }

    return this.uploadService.uploadMultiple(files, type as UploadType);
  }
}