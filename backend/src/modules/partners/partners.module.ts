import { Module }        from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

import { PartnersController } from './partners.controller';
import { PartnersService }    from './partners.service';
import { Partner }            from './entities/partner.entity';
import { CommonModule }       from '../../common/common.module';
import { UploadModule }       from '../upload/upload.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Partner]),
    CommonModule,
    // UploadService : contrôle « logo issu de notre stockage ».
    UploadModule,
  ],
  controllers: [PartnersController],
  providers:   [PartnersService],
  exports:     [PartnersService, TypeOrmModule],
})
export class PartnersModule {}