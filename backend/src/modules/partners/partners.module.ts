import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PartnersController } from './partners.controller';
import { PartnersService } from './partners.service';
import { Partner } from './entities/partner.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([Partner]),
  ],
  controllers: [PartnersController],
  providers: [PartnersService],
  exports: [TypeOrmModule],
})
export class PartnersModule {}  